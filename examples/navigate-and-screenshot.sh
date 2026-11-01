#!/usr/bin/env bash
# Open example.com headed (visible on noVNC) and capture a screenshot.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Ensuring container is up…"
docker compose up -d --build

echo "==> Waiting for Xvfb…"
for i in $(seq 1 60); do
  if docker compose exec -T agent-browser xdpyinfo -display :99 >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "==> Live view: http://localhost:6080/vnc.html?autoconnect=true&resize=scale"

echo "==> Open https://example.com (headed)"
docker compose exec -T agent-browser playwright-cli open https://example.com --headed

echo "==> Snapshot (element refs for click/fill)"
docker compose exec -T agent-browser playwright-cli snapshot

echo "==> Screenshot → /artifacts (host: ./artifacts)"
docker compose exec -T agent-browser playwright-cli screenshot --filename=/artifacts/example.png

echo "==> Done. Screenshot on host: ${ROOT}/artifacts/example.png"
echo "    Close session: docker compose exec agent-browser playwright-cli close"
