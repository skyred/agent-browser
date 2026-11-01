#!/usr/bin/env bash
# Start Xvfb + WM + x11vnc + noVNC, then keep the container alive for docker exec + playwright-cli.
set -euo pipefail

DISPLAY="${DISPLAY:-:99}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
VNC_PORT="${VNC_PORT:-5900}"
SCREEN_WIDTH="${SCREEN_WIDTH:-1280}"
SCREEN_HEIGHT="${SCREEN_HEIGHT:-800}"
SCREEN_DEPTH="${SCREEN_DEPTH:-24}"
NOVNC_PASSWORD="${NOVNC_PASSWORD:-}"

export DISPLAY

echo "[entrypoint] DISPLAY=${DISPLAY} NOVNC_PORT=${NOVNC_PORT}"

# --- Xvfb ---
echo "[entrypoint] starting Xvfb on ${DISPLAY}"
Xvfb "${DISPLAY}" -screen 0 "${SCREEN_WIDTH}x${SCREEN_HEIGHT}x${SCREEN_DEPTH}" -ac +extension GLX +render -noreset &
XVFB_PID=$!

for i in $(seq 1 50); do
  if xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1; then
    echo "[entrypoint] Xvfb ready"
    break
  fi
  sleep 0.1
  if [[ $i -eq 50 ]]; then
    echo "[entrypoint] ERROR: Xvfb failed to start" >&2
    exit 1
  fi
done

# --- Window manager ---
echo "[entrypoint] starting openbox"
openbox &
WM_PID=$!
sleep 0.3

# --- x11vnc ---
if [[ -n "${NOVNC_PASSWORD}" ]]; then
  PASSFILE="${HOME}/.vncpass"
  x11vnc -storepasswd "${NOVNC_PASSWORD}" "${PASSFILE}"
  VNC_ARGS=(-display "${DISPLAY}" -forever -shared -rfbport "${VNC_PORT}" -localhost -rfbauth "${PASSFILE}")
  echo "[entrypoint] VNC password authentication enabled"
else
  VNC_ARGS=(-display "${DISPLAY}" -forever -shared -rfbport "${VNC_PORT}" -localhost -nopw)
  echo "[entrypoint] VNC with no password (bind localhost only; exposed via noVNC)"
fi

echo "[entrypoint] starting x11vnc on :${VNC_PORT}"
x11vnc "${VNC_ARGS[@]}" &
X11VNC_PID=$!
sleep 0.5

# --- noVNC + websockify ---
NOVNC_ROOT="${NOVNC_HOME:-/opt/novnc}"
WEBSOCKIFY_BIN="$(command -v websockify || true)"
if [[ -z "${WEBSOCKIFY_BIN}" ]]; then
  WEBSOCKIFY_BIN="python3 -m websockify"
fi

echo "[entrypoint] starting noVNC on :${NOVNC_PORT}"
if [[ -x "${NOVNC_ROOT}/utils/novnc_proxy" ]]; then
  "${NOVNC_ROOT}/utils/novnc_proxy" --vnc "127.0.0.1:${VNC_PORT}" --listen "${NOVNC_PORT}" &
elif [[ -x "${NOVNC_ROOT}/utils/launch.sh" ]]; then
  "${NOVNC_ROOT}/utils/launch.sh" --vnc "127.0.0.1:${VNC_PORT}" --listen "${NOVNC_PORT}" &
else
  # shellcheck disable=SC2086
  ${WEBSOCKIFY_BIN} --web "${NOVNC_ROOT}" "${NOVNC_PORT}" "127.0.0.1:${VNC_PORT}" &
fi
NOVNC_PID=$!
sleep 0.5

cleanup() {
  echo "[entrypoint] shutting down…"
  kill "${NOVNC_PID:-}" 2>/dev/null || true
  kill "${X11VNC_PID:-}" 2>/dev/null || true
  kill "${WM_PID:-}" 2>/dev/null || true
  kill "${XVFB_PID:-}" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup SIGTERM SIGINT EXIT

echo "[entrypoint] ready — noVNC http://localhost:${NOVNC_PORT}/"
echo "[entrypoint] tip: open http://localhost:${NOVNC_PORT}/vnc.html?autoconnect=true&resize=scale"
echo "[entrypoint] drive with: docker compose exec agent-browser playwright-cli <cmd>"
echo "[entrypoint] DISPLAY=${DISPLAY} playwright-cli=$(command -v playwright-cli || echo missing)"

# Keep container alive for docker exec; do NOT start a custom control server or MCP.
while true; do
  sleep 3600
done
