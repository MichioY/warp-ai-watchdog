#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_SRC="${ROOT_DIR}/warp-ai-watchdog.sh"
SERVICE_SRC="${ROOT_DIR}/systemd/warp-ai-watchdog.service"
TIMER_SRC="${ROOT_DIR}/systemd/warp-ai-watchdog.timer"

BIN_DST="/usr/local/bin/warp-ai-watchdog"
ENV_DST="/etc/default/warp-ai-watchdog"
SERVICE_DST="/etc/systemd/system/warp-ai-watchdog.service"
TIMER_DST="/etc/systemd/system/warp-ai-watchdog.timer"

[[ $EUID -eq 0 ]] || {
  echo "Run as root." >&2
  exit 1
}

install -Dm755 "$BIN_SRC" "$BIN_DST"
install -Dm644 "$SERVICE_SRC" "$SERVICE_DST"
install -Dm644 "$TIMER_SRC" "$TIMER_DST"

if [[ ! -f "$ENV_DST" ]]; then
  install -Dm644 /dev/null "$ENV_DST"
  cat >"$ENV_DST" <<'CONF'
SOCKS_HOST=127.0.0.1
SOCKS_PORT=40000
OPENAI_URL=https://chat.openai.com/cdn-cgi/trace
GEMINI_URL=https://gemini.google.com/
MAX_ATTEMPTS=3
CURL_TIMEOUT=25
GEMINI_TIMEOUT=35
MAX_REDIRS=8
DISCONNECT_SLEEP=3
CONNECT_SLEEP=8
SERVICE_RESTART_SLEEP=8
LOG_FILE=/var/log/warp-ai-watchdog.log
STATE_DIR=/var/lib/warp-ai-watchdog
CONF
fi

mkdir -p /var/lib/warp-ai-watchdog /var/log
touch /var/log/warp-ai-watchdog.log

systemctl daemon-reload
systemctl enable --now warp-ai-watchdog.timer
systemctl start warp-ai-watchdog.service || true

echo "Installed."
echo "Config: $ENV_DST"
echo "Timer:  warp-ai-watchdog.timer"
echo "Logs:   /var/log/warp-ai-watchdog.log"
