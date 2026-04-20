#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || {
  echo "Run as root." >&2
  exit 1
}

systemctl disable --now warp-ai-watchdog.timer >/dev/null 2>&1 || true
systemctl stop warp-ai-watchdog.service >/dev/null 2>&1 || true
rm -f /etc/systemd/system/warp-ai-watchdog.service
rm -f /etc/systemd/system/warp-ai-watchdog.timer
rm -f /usr/local/bin/warp-ai-watchdog
systemctl daemon-reload

echo "Removed service files and binary."
echo "Kept config and logs:"
echo "  /etc/default/warp-ai-watchdog"
echo "  /var/log/warp-ai-watchdog.log"
echo "  /var/lib/warp-ai-watchdog"
