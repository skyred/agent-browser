#!/usr/bin/env bash
# Open a page and print an accessibility snapshot (refs for LLM agents).
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose up -d
docker compose exec -T agent-browser playwright-cli open https://example.com --headed
docker compose exec -T agent-browser playwright-cli snapshot
