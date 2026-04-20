#!/usr/bin/env bash
# [PROTOCOL]
# Purpose: Remove installed service files and the binary while keeping operator data.
# Inputs: Root privileges on a host where the watchdog has been installed.
# Outputs: Deletes installed unit files and binary, preserves env/log/state directories.
# Invariants: Never removes /etc/default/warp-ai-watchdog or runtime logs by default.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: sudo ./uninstall.sh

Removes:
  /usr/local/bin/warp-ai-watchdog
  /etc/systemd/system/warp-ai-watchdog.service
  /etc/systemd/system/warp-ai-watchdog.timer

Keeps:
  /etc/default/warp-ai-watchdog
  /var/log/warp-ai-watchdog.log
  /var/lib/warp-ai-watchdog
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
