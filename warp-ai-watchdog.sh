#!/usr/bin/env bash
# [PROTOCOL]
# Purpose: Probe WARP-backed AI reachability and rotate WARP when probes degrade.
# Inputs: Environment variables, local SOCKS listener, warp-cli, systemd warp service.
# Outputs: Exit status plus append-only operational logs under LOG_FILE.
# Invariants: Never edits WARP registration, never runs concurrently, only heals via local reconnects.
set -euo pipefail

LOG_FILE="${LOG_FILE:-/var/log/warp-ai-watchdog.log}"
STATE_DIR="${STATE_DIR:-/var/lib/warp-ai-watchdog}"
LOCK_FILE="${LOCK_FILE:-/run/warp-ai-watchdog.lock}"

SOCKS_HOST="${SOCKS_HOST:-127.0.0.1}"
SOCKS_PORT="${SOCKS_PORT:-40000}"
OPENAI_URL="${OPENAI_URL:-https://chat.openai.com/cdn-cgi/trace}"
GEMINI_URL="${GEMINI_URL:-https://gemini.google.com/}"
USER_AGENT="${USER_AGENT:-Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36}"

MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"
CURL_TIMEOUT="${CURL_TIMEOUT:-25}"
GEMINI_TIMEOUT="${GEMINI_TIMEOUT:-35}"
MAX_REDIRS="${MAX_REDIRS:-8}"
DISCONNECT_SLEEP="${DISCONNECT_SLEEP:-3}"
CONNECT_SLEEP="${CONNECT_SLEEP:-8}"
SERVICE_RESTART_SLEEP="${SERVICE_RESTART_SLEEP:-8}"

WARP_CLI_BIN="${WARP_CLI_BIN:-warp-cli}"
WARP_SERVICE_NAME="${WARP_SERVICE_NAME:-warp-svc}"

COOKIE_JAR="${STATE_DIR}/gemini-cookiejar.txt"

log() {
  printf '%s %s\n' "$(date -Is)" "$*" >>"$LOG_FILE"
}

require_bin() {
  local bin="$1"
  command -v "$bin" >/dev/null 2>&1 || {
    log "missing_binary: ${bin}"
    return 1
  }
}

prepare_runtime() {
  mkdir -p "$(dirname "$LOG_FILE")" "$STATE_DIR" /run
}

acquire_lock() {
  exec 9>"$LOCK_FILE"
  flock -n 9 || exit 0
}

probe_proxy() {
  printf '%s:%s' "$SOCKS_HOST" "$SOCKS_PORT"
}

probe_openai() {
  curl \
    --socks5-hostname "$(probe_proxy)" \
    -fsS \
    -m "$CURL_TIMEOUT" \
    "$OPENAI_URL"
}

current_ip() {
  probe_openai | awk -F= '/^ip=/{print $2; exit}'
}

probe_gemini_headers() {
  : >"$COOKIE_JAR"
  curl \
    --socks5-hostname "$(probe_proxy)" \
    -sS \
    -m "$GEMINI_TIMEOUT" \
    --max-redirs "$MAX_REDIRS" \
    -A "$USER_AGENT" \
    -c "$COOKIE_JAR" \
    -b "$COOKIE_JAR" \
    -L \
    -D - \
    -o /dev/null \
    -w '\nCURL_HTTP_CODE=%{http_code}\nCURL_EFFECTIVE_URL=%{url_effective}\n' \
    "$GEMINI_URL"
}

healthy_openai() {
  local trace
  trace="$(probe_openai || true)"
  grep -q '^warp=on$' <<<"$trace" && grep -q '^ip=' <<<"$trace"
}

healthy_gemini() {
  local headers rc=0
  headers="$(probe_gemini_headers 2>&1)" || rc=$?
  if [[ $rc -ne 0 ]]; then
    log "gemini_probe_rc=${rc}"
    return 1
  fi
  if grep -qi 'location: https://www.google.com/sorry/index' <<<"$headers"; then
    log "gemini_probe=sorry"
    return 1
  fi
  if grep -qi '^CURL_EFFECTIVE_URL=.*google\.com/sorry/' <<<"$headers"; then
    log "gemini_probe=effective_sorry"
    return 1
  fi
  if grep -qi '^HTTP/2 200' <<<"$headers" || grep -qi '^HTTP/1.1 200' <<<"$headers"; then
    return 0
  fi
  log "gemini_probe=unexpected"
  return 1
}

heal_once() {
  local before_ip after_ip changed=no
  before_ip="$(current_ip 2>/dev/null || true)"
  log "heal_start before_ip=${before_ip:-unknown}"

  if command -v "$WARP_CLI_BIN" >/dev/null 2>&1; then
    "$WARP_CLI_BIN" disconnect >>"$LOG_FILE" 2>&1 || true
    sleep "$DISCONNECT_SLEEP"
    "$WARP_CLI_BIN" connect >>"$LOG_FILE" 2>&1 || true
    sleep "$CONNECT_SLEEP"
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart "$WARP_SERVICE_NAME" >>"$LOG_FILE" 2>&1 || true
    sleep "$SERVICE_RESTART_SLEEP"
  fi

  after_ip="$(current_ip 2>/dev/null || true)"
  if [[ -n "$before_ip" && -n "$after_ip" && "$before_ip" != "$after_ip" ]]; then
    changed=yes
  fi
  log "heal_done after_ip=${after_ip:-unknown} changed=${changed}"
}

run_once() {
  local ok_openai=0 ok_gemini=0 attempt=0 ip_now=""

  prepare_runtime
  require_bin curl || return 1
  require_bin flock || return 1
  acquire_lock

  ip_now="$(current_ip 2>/dev/null || true)"
  healthy_openai && ok_openai=1 || true
  healthy_gemini && ok_gemini=1 || true

  if [[ $ok_openai -eq 1 && $ok_gemini -eq 1 ]]; then
    log "ok openai=1 gemini=1 ip=${ip_now:-unknown}"
    return 0
  fi

  log "degraded openai=${ok_openai} gemini=${ok_gemini} ip=${ip_now:-unknown}"
  for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
    heal_once
    ip_now="$(current_ip 2>/dev/null || true)"
    healthy_openai && ok_openai=1 || ok_openai=0
    healthy_gemini && ok_gemini=1 || ok_gemini=0

    if [[ $ok_openai -eq 1 && $ok_gemini -eq 1 ]]; then
      log "recovered attempt=${attempt} openai=1 gemini=1 ip=${ip_now:-unknown}"
      return 0
    fi
    log "attempt_failed attempt=${attempt} openai=${ok_openai} gemini=${ok_gemini} ip=${ip_now:-unknown}"
  done

  log "still_degraded openai=${ok_openai} gemini=${ok_gemini} ip=${ip_now:-unknown}"
  return 1
}

main() {
  case "${1:---run}" in
    --run)
      run_once
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: warp-ai-watchdog.sh --run

Environment variables:
  SOCKS_HOST
  SOCKS_PORT
  OPENAI_URL
  GEMINI_URL
  MAX_ATTEMPTS
  CURL_TIMEOUT
  GEMINI_TIMEOUT
  MAX_REDIRS
  DISCONNECT_SLEEP
  CONNECT_SLEEP
  SERVICE_RESTART_SLEEP
  WARP_CLI_BIN
  WARP_SERVICE_NAME
  USER_AGENT
  LOG_FILE
  STATE_DIR
  LOCK_FILE
USAGE
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
}

main "$@"
