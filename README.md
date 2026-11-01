# agent-browser

[![Docker Image](https://img.shields.io/docker/v/insready/agent-browser?sort=semver&label=docker)](https://hub.docker.com/r/insready/agent-browser)
[![Publish](https://github.com/skyred/agent-browser/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/skyred/agent-browser/actions/workflows/docker-publish.yml)

A Docker image that gives an AI agent a **real, headed Chromium** to drive, and gives you a **live view** of it in your browser.

- The agent controls the browser with Microsoft's official [`@playwright/cli`](https://www.npmjs.com/package/@playwright/cli) (`playwright-cli`) through `docker exec`.
- You watch the same screen at **http://localhost:6080** over noVNC.
- An LLM skill ([`skills/agent-browser/SKILL.md`](skills/agent-browser/SKILL.md)) teaches the agent how to use it.
- Works with Claude, OpenAI, Grok, DeepSeek, and local Ollama models. See [Connect it to your LLM](#connect-it-to-your-llm).

There is no custom control server and no MCP server. Only the noVNC port is published.

## Why

- **CLI over MCP for token efficiency.** A short `playwright-cli snapshot` or `click e15` costs far fewer tokens than loading a large MCP tool schema and verbose page trees into context on every turn.
- **Headed, not headless.** Chromium runs on a virtual X display (Xvfb), so pages behave like a real desktop browser and you can see what the agent does.
- **Live view.** noVNC streams that display to any web browser. You can watch, and step in to help (for example, a login or captcha).
- **Persistent sessions.** A named Docker volume keeps the `playwright-cli` session cache across container restarts.
- **Pinned and reproducible.** Base image `mcr.microsoft.com/playwright:v1.63.0-noble`, `@playwright/cli@0.1.20`.

## Quick start

### Docker Hub image

```bash
docker run -d --name agent-browser \
  -p 127.0.0.1:6080:6080 \
  --shm-size=1g \
  -v "$PWD/artifacts:/artifacts" \
  -v agent-browser-sessions:/home/pwuser/.cache/ms-playwright \
  insready/agent-browser:latest
```

### Docker Compose (from source)

```bash
git clone https://github.com/skyred/agent-browser.git
cd agent-browser
docker compose up -d --build     # or: make up
```

Then open the live view:

**http://localhost:6080/vnc.html?autoconnect=true&resize=scale**

Stop with `docker compose down` (or `make down`).

## Drive the browser

Run `playwright-cli` inside the container. With Compose, use `docker compose exec agent-browser …`; with `docker run`, use `docker exec agent-browser …`.

```bash
docker compose exec agent-browser playwright-cli open https://example.com --headed
docker compose exec agent-browser playwright-cli snapshot          # a11y tree with element refs (e3, e15, …)
docker compose exec agent-browser playwright-cli click e15
docker compose exec agent-browser playwright-cli fill e7 "hello" --submit
docker compose exec agent-browser playwright-cli screenshot --filename=/artifacts/page.png
docker compose exec agent-browser playwright-cli close
```

Shortcut: `make cli CMD='open https://example.com --headed'`. Inside the image, `pw` is an alias for `playwright-cli`.

### Cheat sheet

```text
playwright-cli open [url] --headed           # start headed browser (visible on noVNC)
playwright-cli goto <url>
playwright-cli snapshot                      # a11y tree + element refs
playwright-cli click <ref>
playwright-cli type <text>
playwright-cli fill <ref> <text> [--submit]
playwright-cli press <key>
playwright-cli screenshot [--filename=/artifacts/x.png]
playwright-cli eval <js>
playwright-cli -s=name open <url> --headed   # named session
playwright-cli list
playwright-cli close | close-all
```

Full reference: `playwright-cli --help` and [microsoft/playwright-cli](https://github.com/microsoft/playwright-cli).

### Examples

- [`examples/navigate-and-screenshot.sh`](examples/navigate-and-screenshot.sh): start the stack, open example.com, snapshot, save `./artifacts/example.png`.
- [`examples/snapshot-demo.sh`](examples/snapshot-demo.sh): open a page and print its snapshot.

## Install the agent skill

[`skills/agent-browser/SKILL.md`](skills/agent-browser/SKILL.md) tells an LLM agent when to use this stack, how to start it, the `open → snapshot → click/fill → screenshot` loop, sessions, and troubleshooting. Copy or symlink the folder into your agent's skills directory, for example:

```bash
# Claude Code / compatible agents
mkdir -p ~/.claude/skills
ln -s "$PWD/skills/agent-browser" ~/.claude/skills/agent-browser
```

The skill uses `docker compose` commands, so the agent should run them from this project directory.

## Connect it to your LLM

There is no server to register. The model drives the browser by running shell commands such as `docker compose exec agent-browser playwright-cli snapshot`. Every integration is the same two pieces:

1. **A shell tool** the model can call, restricted to `playwright-cli` inside the container.
2. **The instructions** in [`skills/agent-browser/SKILL.md`](skills/agent-browser/SKILL.md), loaded as a skill or as the system prompt.

Start the stack first (`docker compose up -d`) and open the [live view](http://localhost:6080/vnc.html?autoconnect=true&resize=scale) to watch.

> **Security: never give an LLM an unrestricted shell.** Pages the agent reads can contain prompt injection. Allowlist only `playwright-cli` in the `agent-browser` container, and require approval for anything else. [`examples/agent_loop.py`](examples/agent_loop.py) enforces this: it rejects any command that isn't `playwright-cli …` and runs the argv with `docker exec` directly, never through a shell.

### Coding agents (skill-based)

**Claude Code.** Skills are folders with a `SKILL.md` in `~/.claude/skills/<name>/` (all projects) or `.claude/skills/<name>/` (this repo). Symlinks are supported.

```bash
mkdir -p ~/.claude/skills
ln -s "$PWD/skills/agent-browser" ~/.claude/skills/agent-browser
```

Claude loads the skill when a task needs a browser, or invoke it with `/agent-browser`. To skip the permission prompt for browser commands only, add an allow rule such as `Bash(docker compose exec agent-browser playwright-cli *)` in `/permissions`. Don't allow `Bash(*)`.

**OpenAI Codex CLI.** Codex reads skills from `.agents/skills/` (repo) or `~/.agents/skills/` (user), and follows symlinks:

```bash
mkdir -p ~/.agents/skills
ln -s "$PWD/skills/agent-browser" ~/.agents/skills/agent-browser
```

Mention it with `$` or `/skills`, or let Codex pick it from the description. Keep Codex's sandbox/approval settings on so it asks before running commands outside the allowlist.

**Other agents (Cursor, Aider, …).** Any agent that can run shell commands and read instructions works. Point it at the skill file, for example from your project's `AGENTS.md` ("For browser tasks, follow `skills/agent-browser/SKILL.md`"), or `aider --read skills/agent-browser/SKILL.md`. Restrict its terminal to `playwright-cli` commands where the agent supports it.

### API models (generic agent loop)

[`examples/agent_loop.py`](examples/agent_loop.py) is a ~150-line agent loop for any **OpenAI-compatible** Chat Completions API. It uses the skill as the system prompt and exposes one tool, `run_shell`, that only runs `playwright-cli` in the container.

```bash
pip install openai
docker compose up -d
export BASE_URL=... API_KEY=... MODEL=...     # see the provider table below
python examples/agent_loop.py "Open example.com and tell me the main heading"
```

The tool definition the model sees:

```python
{"type": "function", "function": {
    "name": "run_shell",
    "description": "Run ONE playwright-cli command inside the agent-browser container ...",
    "parameters": {"type": "object",
                   "properties": {"command": {"type": "string"}},
                   "required": ["command"]}}}
```

Optional env vars: `CONTAINER` (default `agent-browser`), `SKILL_FILE`, `MAX_STEPS` (default 30).

| Provider | `BASE_URL` | `API_KEY` | `MODEL` (examples) |
|----------|-----------|-----------|--------------------|
| OpenAI | `https://api.openai.com/v1` | OpenAI key | `gpt-6.1-sol`, `gpt-6-astra` |
| Claude (Anthropic) | `https://api.anthropic.com/v1/` | Claude API key | `claude-opus-5-5`, `claude-sonnet-4-6` |
| Grok (xAI) | `https://api.x.ai/v1` | xAI key | `grok-4.7` |
| DeepSeek | `https://api.deepseek.com` | DeepSeek key | `deepseek-flash`, `deepseek-v4-pro` |
| Ollama (local) | `http://localhost:11434/v1` | any string, e.g. `ollama` | `qwen3`, `gpt-oss:20b` |

Model names change often; check each provider's model list.

**OpenAI**

```bash
export BASE_URL=https://api.openai.com/v1 API_KEY=$OPENAI_API_KEY MODEL=gpt-6.1-sol
```

**Claude API / Claude Desktop.** The loop works through Anthropic's [OpenAI SDK compatibility](https://platform.claude.com/docs/en/api/openai-sdk) layer (Anthropic recommends the native API for production; port the same single tool to the Messages API if you need its full features):

```bash
export BASE_URL=https://api.anthropic.com/v1/ API_KEY=$ANTHROPIC_API_KEY MODEL=claude-opus-5-5
```

Claude Desktop has no built-in shell, so use Claude Code (above) for this stack.

**Grok (xAI)**

```bash
export BASE_URL=https://api.x.ai/v1 API_KEY=$XAI_API_KEY MODEL=grok-4.7
```

**DeepSeek**

```bash
export BASE_URL=https://api.deepseek.com API_KEY=$DEEPSEEK_API_KEY MODEL=deepseek-flash
```

**Ollama (local, no API key)**

```bash
ollama pull qwen3
export BASE_URL=http://localhost:11434/v1 API_KEY=ollama MODEL=qwen3
```

Use a model that supports tool calling (see [Ollama tool calling](https://docs.ollama.com/capabilities/tool-calling)); small models may loop or misuse refs, so keep `MAX_STEPS` low. Ollama doesn't need to reach the container: the script runs on the host, talks to Ollama on `localhost:11434`, and drives the browser with `docker exec`. If you run the agent loop inside another container, use `http://host.docker.internal:11434/v1` (add `extra_hosts: ["host.docker.internal:host-gateway"]` on Linux) and mount the Docker socket only if you accept that risk.

## How it works

```text
Your browser ──► :6080 (noVNC)
                    │
                    ▼
   ┌─ container ───────────────────────────────┐
   │  noVNC / websockify → x11vnc (localhost)   │
   │        → Xvfb :99 ← openbox                │
   │        → headed Chromium (Playwright)      │
   │                                            │
   │  Agent: docker exec → playwright-cli       │
   └────────────────────────────────────────────┘
```

The entrypoint (`scripts/entrypoint.sh`) starts Xvfb, openbox, x11vnc (bound to `127.0.0.1:5900` inside the container), and noVNC, then idles so you can `docker exec` into it. The default CLI config (`config/cli.config.json`) forces headed Chromium with Docker-friendly flags (`--no-sandbox`, `--disable-dev-shm-usage`, `--disable-gpu`), a 1280×800 viewport, and output to `/artifacts`.

## Configuration

### Ports

| Port | Purpose |
|------|---------|
| `6080` | noVNC web UI (the only published port) |
| `5900` | x11vnc, container-local only (not exposed) |

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DISPLAY` | `:99` | X display for headed Chromium |
| `NOVNC_PORT` | `6080` | noVNC listen port |
| `VNC_PORT` | `5900` | Internal x11vnc port |
| `NOVNC_PASSWORD` | _(empty)_ | If set, VNC requires this password |
| `SCREEN_WIDTH` / `SCREEN_HEIGHT` / `SCREEN_DEPTH` | `1280` / `800` / `24` | Xvfb screen size |
| `ARTIFACTS_DIR` | `/artifacts` | Artifact directory |
| `PLAYWRIGHT_MCP_CONFIG` | `/app/.playwright/cli.config.json` | CLI config file |
| `PLAYWRIGHT_MCP_OUTPUT_DIR` | `/artifacts` | CLI output directory |
| `PLAYWRIGHT_MCP_HEADLESS` | `false` | Keep the browser headed |

### Volumes

| Path | Purpose |
|------|---------|
| `/artifacts` | Screenshots and other output. Compose mounts `./artifacts`. Use `--filename=/artifacts/...`. |
| `/home/pwuser/.cache/ms-playwright` | `playwright-cli` session cache. Compose uses the named volume `agent-browser-sessions`. |

Set `shm_size: 1gb` (or `--shm-size=1g`) so Chromium doesn't crash on heavy pages.

### Makefile

| Target | Action |
|--------|--------|
| `make up` | `docker compose up -d --build` |
| `make down` | Stop the stack |
| `make build` | Build the image |
| `make shell` | Bash in the container |
| `make logs` | Follow logs |
| `make cli CMD='…'` | Run `playwright-cli …` in the container |

## Security

- This is a full browser **with outbound network access**. Treat what the agent browses as untrusted.
- **Anyone who can reach port 6080 can watch and control the browser.** VNC has no password by default. `docker-compose.yml` publishes `6080:6080`, which binds to all host interfaces; change it to `127.0.0.1:6080:6080` on shared machines, and set `NOVNC_PASSWORD` or put it behind an authenticated proxy before exposing it further. noVNC is plain HTTP.
- The persistent session volume can hold cookies and logins. Delete it (`docker volume rm agent-browser-sessions`) when you're done with sensitive accounts.
- No secrets are baked into the image or compose file.

## Publishing

`.github/workflows/docker-publish.yml` builds multi-arch images (`linux/amd64`, `linux/arm64`) and pushes them to [`insready/agent-browser`](https://hub.docker.com/r/insready/agent-browser):

| Event | Tags |
|-------|------|
| Push to `main` | `latest`, `main`, `sha-<short>` |
| Tag `v1.2.3` | `1.2.3`, `1.2`, `1`, `latest` |
| Monthly schedule / manual run | `latest` (picks up base-image security updates) |
| Pull request | Build only, no push |

To release: `git tag v2.0.0 && git push origin v2.0.0`.

## Related projects

- [vercel-labs/agent-browser](https://github.com/vercel-labs/agent-browser): a different tool with the same name. It's a Rust browser-automation CLI for agents, with no container or live view.
- [auto-browser](https://github.com/search?q=auto-browser&type=repositories) and [mcp-playwright-novnc](https://github.com/search?q=mcp-playwright-novnc&type=repositories): similar headed-browser-with-noVNC setups, controlled over MCP instead of a CLI.
- [microsoft/playwright-cli](https://github.com/microsoft/playwright-cli): the CLI this image wraps.

## License

MIT. See [LICENSE](LICENSE).
