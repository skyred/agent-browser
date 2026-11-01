#!/usr/bin/env python3
"""Minimal LLM agent loop that drives agent-browser through playwright-cli.

Works with any OpenAI-compatible Chat Completions endpoint (OpenAI, Claude via
Anthropic's OpenAI SDK compatibility layer, xAI Grok, DeepSeek, Ollama, ...).

The model gets exactly ONE tool, `run_shell`, and that tool only runs
`playwright-cli ...` inside the agent-browser container. Nothing else.

    pip install openai
    docker compose up -d
    BASE_URL=... API_KEY=... MODEL=... python examples/agent_loop.py "Open example.com and tell me the heading"

Env vars:
    BASE_URL    OpenAI-compatible base URL (default: https://api.openai.com/v1)
    API_KEY     API key (Ollama ignores it, but the SDK needs a value)
    MODEL       model name (required)
    CONTAINER   docker container name (default: agent-browser)
    SKILL_FILE  system prompt file (default: skills/agent-browser/SKILL.md)
    MAX_STEPS   max tool-call rounds (default: 30)
"""
from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

CONTAINER = os.environ.get("CONTAINER", "agent-browser")
REPO_ROOT = Path(__file__).resolve().parent.parent
SKILL_FILE = Path(os.environ.get("SKILL_FILE", REPO_ROOT / "skills/agent-browser/SKILL.md"))
MAX_STEPS = int(os.environ.get("MAX_STEPS", "30"))
MAX_OUTPUT = 20_000  # chars returned to the model per call
TIMEOUT_S = 120

ALLOWED_PREFIXES = (
    ["playwright-cli"],
    ["docker", "compose", "exec", "agent-browser", "playwright-cli"],
    ["docker", "compose", "exec", "-T", "agent-browser", "playwright-cli"],
    ["docker", "exec", CONTAINER, "playwright-cli"],
    ["pw"],
)
# The argv is executed directly (no shell), so `;`, `|`, `$(...)` are inert text
# (URLs with `&` work). Only control characters are rejected.
FORBIDDEN = set("\n\r\0")

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "run_shell",
            "description": (
                "Run ONE playwright-cli command inside the agent-browser container, e.g. "
                "`playwright-cli open https://example.com --headed`, `playwright-cli snapshot`, "
                "`playwright-cli click e15`. The `docker compose exec agent-browser` prefix is optional. "
                "Any other command is rejected."
            ),
            "parameters": {
                "type": "object",
                "properties": {"command": {"type": "string", "description": "The playwright-cli command line."}},
                "required": ["command"],
            },
        },
    }
]


def parse_command(command: str) -> list[str]:
    """Validate a command and return the playwright-cli argv (without prefix). Raises ValueError."""
    if any(ch in FORBIDDEN for ch in command):
        raise ValueError("control characters are not allowed")
    argv = shlex.split(command)
    for prefix in ALLOWED_PREFIXES:
        if argv[: len(prefix)] == prefix:
            return argv[len(prefix):]
    raise ValueError("only `playwright-cli ...` commands are allowed")


def run_shell(command: str) -> str:
    """The single tool exposed to the model. Never uses shell=True."""
    try:
        args = parse_command(command)
    except ValueError as e:
        return f"REJECTED: {e}"
    argv = ["docker", "exec", CONTAINER, "playwright-cli", *args]
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=TIMEOUT_S)
    except subprocess.TimeoutExpired:
        return f"ERROR: timed out after {TIMEOUT_S}s"
    out = (p.stdout + (("\n[stderr]\n" + p.stderr) if p.stderr.strip() else "")).strip()
    if len(out) > MAX_OUTPUT:
        out = out[:MAX_OUTPUT] + f"\n...[truncated {len(out) - MAX_OUTPUT} chars]"
    return f"exit={p.returncode}\n{out}"


def system_prompt() -> str:
    skill = SKILL_FILE.read_text(encoding="utf-8")
    return (
        "You control a real headed Chromium through the `run_shell` tool, which runs playwright-cli "
        "inside an already-running Docker container. Do not try to start or stop the stack. "
        "Loop: open -> snapshot -> click/fill/press -> snapshot -> answer.\n\n" + skill
    )


def main() -> int:
    from openai import OpenAI  # imported here so `--help`/tests work without the SDK

    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    model = os.environ.get("MODEL")
    if not model:
        sys.exit("Set MODEL (and BASE_URL / API_KEY).")
    client = OpenAI(
        base_url=os.environ.get("BASE_URL", "https://api.openai.com/v1"),
        api_key=os.environ.get("API_KEY") or os.environ.get("OPENAI_API_KEY", "none"),
    )
    messages = [
        {"role": "system", "content": system_prompt()},
        {"role": "user", "content": " ".join(sys.argv[1:])},
    ]
    for _ in range(MAX_STEPS):
        resp = client.chat.completions.create(model=model, messages=messages, tools=TOOLS)
        msg = resp.choices[0].message
        messages.append(msg.model_dump(exclude_none=True))
        if not msg.tool_calls:
            print(msg.content or "")
            return 0
        for call in msg.tool_calls:
            try:
                cmd = json.loads(call.function.arguments or "{}").get("command", "")
            except json.JSONDecodeError:
                cmd = ""
            result = run_shell(cmd) if call.function.name == "run_shell" else "ERROR: unknown tool"
            print(f"$ {cmd}\n{result[:500]}\n", file=sys.stderr)
            messages.append({"role": "tool", "tool_call_id": call.id, "content": result})
    print("Stopped: MAX_STEPS reached.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
