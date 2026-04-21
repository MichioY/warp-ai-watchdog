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
FAIL_COUNT_FILE="${STATE_DIR}/consecutive_failures"

SOCKS_HOST="${SOCKS_HOST:-127.0.0.1}"
SOCKS_PORT="${SOCKS_PORT:-40000}"
OPENAI_URL="${OPENAI_URL:-https://chat.openai.com/cdn-cgi/trace}"
GEMINI_URL="${GEMINI_URL:-https://gemini.google.com/}"
USER_AGENT="${USER_AGENT:-Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36}"

MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"
MIN_CONSECUTIVE_FAILURES="${MIN_CONSECUTIVE_FAILURES:-2}"
VERIFY_RECHECK_DELAY="${VERIFY_RECHECK_DELAY:-3}"
CURL_TIMEOUT="${CURL_TIMEOUT:-25}"
GEMINI_TIMEOUT="${GEMINI_TIMEOUT:-35}"
MAX_REDIRS="${MAX_REDIRS:-8}"
DISCONNECT_SLEEP="${DISCONNECT_SLEEP:-3}"
CONNECT_SLEEP="${CONNECT_SLEEP:-8}"
SERVICE_RESTART_SLEEP="${SERVICE_RESTART_SLEEP:-8}"

WARP_CLI_BIN="${WARP_CLI_BIN:-warp-cli}"
WARP_SERVICE_NAME="${WARP_SERVICE_NAME:-warp-svc}"

COOKIE_JAR="${STATE_DIR}/gemini-cookiejar.txt"
OPENAI_OK=0
GEMINI_OK=0
IP_NOW=""

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
  : >"$COOKIE_JAR"
}

acquire_lock() {
  exec 9>"$LOCK_FILE"
  flock -n 9 || exit 0
}

probe_proxy() {
  printf '%s:%s' "$SOCKS_HOST" "$SOCKS_PORT"
}

warp_service_active() {
  systemctl is-active --quiet "$WARP_SERVICE_NAME"
}

socks_listener_ready() {
  ss -ltn 2>/dev/null | awk -v port=":${SOCKS_PORT}" '$4 ~ (port "$") { found=1 } END { exit(found ? 0 : 1) }'
}

read_fail_count() {
  if [[ -f "$FAIL_COUNT_FILE" ]]; then
    cat "$FAIL_COUNT_FILE"
  else
    echo 0
  fi
}

write_fail_count() {
  printf '%s\n' "$1" >"$FAIL_COUNT_FILE"
}

reset_fail_count() {
  write_fail_count 0
}

increment_fail_count() {
  local count
  count="$(read_fail_count)"
  count=$((count + 1))
  write_fail_count "$count"
  printf '%s\n' "$count"
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
  local trace rc=0
  trace="$(probe_openai 2>&1)" || rc=$?
  if [[ $rc -ne 0 ]]; then
    log "openai_probe_rc=${rc}"
    return 1
  fi
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

measure_health() {
  OPENAI_OK=0
  GEMINI_OK=0
  IP_NOW="$(current_ip 2>/dev/null || true)"

  if healthy_openai; then
    OPENAI_OK=1
  fi
  if healthy_gemini; then
    GEMINI_OK=1
  fi
}

heal_once() {
  local before_ip after_ip changed=no service_active=no listener_ready=no
  before_ip="$(current_ip 2>/dev/null || true)"
  warp_service_active && service_active=yes || true
  socks_listener_ready && listener_ready=yes || true
  log "heal_start before_ip=${before_ip:-unknown} service_active=${service_active} listener_ready=${listener_ready}"

  if [[ "$service_active" == "yes" && "$listener_ready" == "yes" ]]; then
    "$WARP_CLI_BIN" disconnect >>"$LOG_FILE" 2>&1 || true
    sleep "$DISCONNECT_SLEEP"
    "$WARP_CLI_BIN" connect >>"$LOG_FILE" 2>&1 || true
    sleep "$CONNECT_SLEEP"
  fi

  if ! warp_service_active || ! socks_listener_ready; then
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
  local consecutive_failures=0 attempt=0 service_active=no listener_ready=no

  prepare_runtime
  require_bin curl || return 1
  require_bin flock || return 1
  require_bin systemctl || return 1
  require_bin ss || return 1
  require_bin "$WARP_CLI_BIN" || return 1
  acquire_lock

  measure_health

  if [[ $OPENAI_OK -eq 1 && $GEMINI_OK -eq 1 ]]; then
    reset_fail_count
    log "ok openai=1 gemini=1 ip=${IP_NOW:-unknown}"
    return 0
  fi

  warp_service_active && service_active=yes || true
  socks_listener_ready && listener_ready=yes || true

  if [[ "$service_active" == "yes" && "$listener_ready" == "yes" ]]; then
    sleep "$VERIFY_RECHECK_DELAY"
    measure_health
    if [[ $OPENAI_OK -eq 1 && $GEMINI_OK -eq 1 ]]; then
      reset_fail_count
      log "transient_recovered openai=1 gemini=1 ip=${IP_NOW:-unknown}"
      return 0
    fi
  fi

  consecutive_failures="$(increment_fail_count)"
  log "degraded openai=${OPENAI_OK} gemini=${GEMINI_OK} ip=${IP_NOW:-unknown} service_active=${service_active} listener_ready=${listener_ready} consecutive_failures=${consecutive_failures}"

  if [[ "$service_active" == "yes" && "$listener_ready" == "yes" && "$consecutive_failures" -lt "$MIN_CONSECUTIVE_FAILURES" ]]; then
    log "defer_heal threshold=${MIN_CONSECUTIVE_FAILURES} consecutive_failures=${consecutive_failures}"
    return 0
  fi

  for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
    heal_once
    measure_health

    if [[ $OPENAI_OK -eq 1 && $GEMINI_OK -eq 1 ]]; then
      reset_fail_count
      log "recovered attempt=${attempt} openai=1 gemini=1 ip=${IP_NOW:-unknown}"
      return 0
    fi
    log "attempt_failed attempt=${attempt} openai=${OPENAI_OK} gemini=${GEMINI_OK} ip=${IP_NOW:-unknown}"
  done

  log "still_degraded openai=${OPENAI_OK} gemini=${GEMINI_OK} ip=${IP_NOW:-unknown}"
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
  MIN_CONSECUTIVE_FAILURES
  VERIFY_RECHECK_DELAY
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
