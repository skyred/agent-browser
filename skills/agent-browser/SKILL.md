---
name: Agent browser
description: Use when an LLM needs a real headed browser in Docker — start with docker compose, drive with official playwright-cli via docker exec, user watches live on noVNC. Prefer CLI over MCP for token efficiency.
---

# Agent browser

Drive a **real headed Chromium** inside Docker. The user watches live over **noVNC**. You control it with Microsoft’s official **`playwright-cli`** (`@playwright/cli`) via **`docker compose exec`**.

**Prefer CLI over MCP** — shorter invocations, no large tool schemas in context. **Do not start an MCP server** for this stack.

## When to use

- Real browser needed (JS pages, logins, multi-step UI) instead of raw HTTP.
- User should **see** what you do (noVNC).
- Screenshots, accessibility snapshots, or page eval for reasoning.

## Start the stack

From the project root (`agent-browser/`):

```bash
docker compose up -d --build
# or: make up
```

Tell the user the live URL:

**http://localhost:6080/vnc.html?autoconnect=true&resize=scale**

Only port **6080** is published (no control HTTP API).

## How to drive

All commands run **inside** the container:

```bash
docker compose exec agent-browser playwright-cli <cmd>
# or: make cli CMD='<cmd>'
# alias inside image: pw <cmd>
```

### Always headed for live view

Default image config sets `browser.launchOptions.headless: false`. Still pass **`--headed`** on `open` so the window appears on Xvfb/noVNC:

```bash
docker compose exec agent-browser playwright-cli open https://example.com --headed
```

### Core agent loop

1. **`open URL --headed`** — start / navigate (user sees it on noVNC).
2. **`snapshot`** — get accessibility tree and element **refs** (`e3`, `e15`, …).
3. **`click` / `type` / `fill` / `press`** using those refs.
4. **`screenshot`** — evidence under `/artifacts` (host: `./artifacts`).
5. Repeat snapshot → act as needed; **`close`** when done.

```bash
docker compose exec agent-browser playwright-cli open https://example.com --headed
docker compose exec agent-browser playwright-cli snapshot
docker compose exec agent-browser playwright-cli click e2
docker compose exec agent-browser playwright-cli fill e5 "hello" --submit
docker compose exec agent-browser playwright-cli screenshot --filename=/artifacts/step.png
docker compose exec agent-browser playwright-cli close
```

### Sessions

```bash
docker compose exec agent-browser playwright-cli -s=work open https://example.com --headed
docker compose exec agent-browser playwright-cli -s=work snapshot
docker compose exec agent-browser playwright-cli list
docker compose exec agent-browser playwright-cli -s=work close
docker compose exec agent-browser playwright-cli close-all
```

Env alternative: `PLAYWRIGHT_CLI_SESSION=work` inside the container.

### Useful commands

```text
open [url] --headed | goto <url> | go-back | go-forward | reload
snapshot [--depth=N] | find "text" | eval <js> [ref]
click <ref> | dblclick <ref> | hover <ref> | type <text> | fill <ref> <text> [--submit]
press <key> | check <ref> | uncheck <ref> | select <ref> <val>
screenshot [--filename=/artifacts/x.png] | pdf
tab-list | tab-new [url] | tab-select <n> | tab-close [n]
list | close | close-all
--raw … | --json …     # machine-friendly output
```

Run `playwright-cli --help` inside the container for the full list.

## Artifacts

| Where | Path |
|-------|------|
| Container | `/artifacts` |
| Host (compose mount) | `./artifacts` |
| Default CLI config | `/app/.playwright/cli.config.json` |

Write screenshots with `--filename=/artifacts/...` so they land on the host.

## Troubleshooting

| Symptom | What to try |
|--------|-------------|
| `docker compose exec` fails / no container | `docker compose up -d --build`, `docker compose ps`, `make logs` |
| Blank / gray noVNC | Open autoconnect URL; wait for Xvfb; run `open … --headed`; `xdpyinfo -display :99` in container |
| Browser not visible | Must be headed (`--headed` or default config); check `DISPLAY=:99` |
| Click/type miss | Fresh `snapshot` for refs; `find "label"`; increase patience / reload |
| Screenshots missing on host | Path under `/artifacts`; confirm compose volume `./artifacts:/artifacts` |
| OOM / crash | Compose `shm_size: 1gb`; raise if needed |
| Stale session | `playwright-cli close` or `close-all`, then `open` again |

```bash
make logs
make shell
docker compose restart agent-browser
```

## Security note

Full browser with network access. Anyone who can reach noVNC (**6080**) can watch the session. Bind to localhost / trusted networks; optional `NOVNC_PASSWORD`. Never put secrets in the image or compose file. Prefer CLI (no published control port) over MCP.

## Do not

- Do **not** start Playwright MCP or any custom Express control server.
- Do **not** reinvent `agent-browser navigate` — use **`playwright-cli`**.
- Do **not** open headless-only if the user expects to watch on noVNC.
