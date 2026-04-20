#!/usr/bin/env bash
# [PROTOCOL]
# Purpose: Install the watchdog script, default environment file, and systemd units.
# Inputs: Repository-local script/unit files plus root privileges on the target host.
# Outputs: Installed files under /usr/local/bin, /etc/default, and /etc/systemd/system.
# Invariants: Does not overwrite an existing env file, enables the timer, starts one immediate health cycle.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_SRC="${ROOT_DIR}/warp-ai-watchdog.sh"
SERVICE_SRC="${ROOT_DIR}/systemd/warp-ai-watchdog.service"
TIMER_SRC="${ROOT_DIR}/systemd/warp-ai-watchdog.timer"
ENV_SRC="${ROOT_DIR}/warp-ai-watchdog.env.example"

BIN_DST="/usr/local/bin/warp-ai-watchdog"
ENV_DST="/etc/default/warp-ai-watchdog"
SERVICE_DST="/etc/systemd/system/warp-ai-watchdog.service"
TIMER_DST="/etc/systemd/system/warp-ai-watchdog.timer"

usage() {
  cat <<'USAGE'
Usage: sudo ./install.sh

Installs:
  /usr/local/bin/warp-ai-watchdog
  /etc/default/warp-ai-watchdog
  /etc/systemd/system/warp-ai-watchdog.service
  /etc/systemd/system/warp-ai-watchdog.timer

Notes:
  - Existing /etc/default/warp-ai-watchdog is preserved.
  - Timer cadence is defined in systemd/warp-ai-watchdog.timer.
USAGE
}

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    echo "Unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
esac

[[ $EUID -eq 0 ]] || {
  echo "Run as root." >&2
  exit 1
}

install -Dm755 "$BIN_SRC" "$BIN_DST"
install -Dm644 "$SERVICE_SRC" "$SERVICE_DST"
install -Dm644 "$TIMER_SRC" "$TIMER_DST"

if [[ ! -f "$ENV_DST" ]]; then
  install -Dm644 "$ENV_SRC" "$ENV_DST"
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
