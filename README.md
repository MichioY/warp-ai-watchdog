# warp-ai-watchdog

[![CI](https://github.com/MichioY/warp-ai-watchdog/actions/workflows/ci.yml/badge.svg)](https://github.com/MichioY/warp-ai-watchdog/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/MichioY/warp-ai-watchdog)](https://github.com/MichioY/warp-ai-watchdog/releases)

中文说明见：[README.zh-CN.md](README.zh-CN.md)

`warp-ai-watchdog` is a small watchdog for WARP-based AI routing on Linux hosts.

It probes a WARP SOCKS endpoint with browser-adjacent checks for services like
OpenAI and Gemini, and automatically reconnects WARP when the current exit IP
looks degraded.

The project is intentionally narrow:

- It does not manage your proxy stack.
- It does not promise a permanently "clean" IP.
- It only answers one practical question:
  "Is the current WARP exit good enough for the AI services I care about?"

If the answer is "no", it rotates the WARP session and checks again.

## Why This Exists

Some AI services are sensitive to exit reputation and mixed egress paths.

Typical failures look like:

- Google Gemini bouncing through `sorry/index`
- alternating `google_abuse` redirects
- OpenAI no longer showing `warp=on`
- a previously good WARP IP becoming poor later

This project makes that operationally boring:

- probe
- decide healthy or degraded
- reconnect WARP
- verify again
- repeat for a limited number of attempts

## What It Checks

The watchdog currently performs two health checks through the configured SOCKS
proxy:

- OpenAI trace check
  - expects a valid `ip=...` line
  - expects `warp=on`
- Gemini browser-adjacent check
  - follows redirects with a cookie jar
  - treats `sorry/index` as degraded
  - treats final `HTTP 200` as healthy

These checks are practical heuristics, not formal guarantees.

## Requirements

- Linux host with `systemd`
- Cloudflare WARP client installed
- `warp-cli`
- `warp-svc`
- a local SOCKS listener exposed by WARP
  - default: `127.0.0.1:40000`
- `bash`, `curl`, `flock`

## When To Use It

Use this project when:

- WARP is already part of your routing path
- AI services intermittently fail because the current exit reputation is poor
- you want an operator-safe local auto-heal loop instead of manual reconnects

Do not use this project as:

- a generic proxy manager
- a panel replacement
- a cross-platform desktop tool
- a guarantee of permanent Gemini or OpenAI reachability

## Repository Layout

- `warp-ai-watchdog.sh`
  - main watchdog script
- `install.sh`
  - installs the script, config file, and systemd units
- `uninstall.sh`
  - removes the installed components
- `warp-ai-watchdog.env.example`
  - example environment file
- `systemd/warp-ai-watchdog.service`
  - oneshot service
- `systemd/warp-ai-watchdog.timer`
  - periodic timer

## Quick Start

```bash
git clone <repo-url>
cd warp-ai-watchdog
sudo ./install.sh
```

Review the generated config at:

```bash
sudo sed -n '1,200p' /etc/default/warp-ai-watchdog
```

After install:

```bash
sudo systemctl status warp-ai-watchdog.timer
sudo systemctl start warp-ai-watchdog.service
sudo tail -f /var/log/warp-ai-watchdog.log
```

## Configuration

The installer writes `/etc/default/warp-ai-watchdog`.

You can also start from the repository example:

```bash
cp warp-ai-watchdog.env.example /tmp/warp-ai-watchdog.env
```

Supported settings:

```bash
SOCKS_HOST=127.0.0.1
SOCKS_PORT=40000
OPENAI_URL=https://chat.openai.com/cdn-cgi/trace
GEMINI_URL=https://gemini.google.com/
USER_AGENT=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36
MAX_ATTEMPTS=3
MIN_CONSECUTIVE_FAILURES=2
VERIFY_RECHECK_DELAY=3
CURL_TIMEOUT=25
GEMINI_TIMEOUT=35
MAX_REDIRS=8
DISCONNECT_SLEEP=3
CONNECT_SLEEP=8
SERVICE_RESTART_SLEEP=8
WARP_CLI_BIN=warp-cli
WARP_SERVICE_NAME=warp-svc
LOG_FILE=/var/log/warp-ai-watchdog.log
STATE_DIR=/var/lib/warp-ai-watchdog
LOCK_FILE=/run/warp-ai-watchdog.lock
```

After editing the config:

```bash
sudo systemctl daemon-reload
sudo systemctl restart warp-ai-watchdog.timer
sudo systemctl start warp-ai-watchdog.service
```

Timer cadence is configured in [`systemd/warp-ai-watchdog.timer`](systemd/warp-ai-watchdog.timer).
If you want a different interval, edit the timer unit and reload systemd.

## Health Logic

The watchdog uses this decision model:

1. Probe OpenAI through WARP.
2. Probe Gemini through WARP using redirects plus a cookie jar.
3. If both are healthy, reset the failure counter and exit cleanly.
4. If the service is up and the SOCKS listener exists, wait `VERIFY_RECHECK_DELAY`
   seconds and probe once more before taking recovery action.
5. If degradation is only transient, reset the failure counter and exit cleanly.
6. If degradation persists, increment a consecutive failure counter.
7. Only heal immediately when:
   - `warp-svc` is not active, or
   - the SOCKS listener is missing, or
   - the failure counter has reached `MIN_CONSECUTIVE_FAILURES`
8. Healing is staged:
   - first try `warp-cli disconnect` plus `warp-cli connect` when the service is
     still up
   - then restart `warp-svc` only if the service or listener is still unhealthy
9. Stop after `MAX_ATTEMPTS`.

This means the watchdog does not look for a theoretically "clean" IP. It looks
for an IP that passes the actual site probes now, while avoiding unnecessary
session churn from one-off probe failures.

## Verification

Run one cycle manually:

```bash
sudo /usr/local/bin/warp-ai-watchdog --run
echo $?
```

Inspect recent logs:

```bash
sudo tail -n 50 /var/log/warp-ai-watchdog.log
```

Inspect timer state:

```bash
sudo systemctl list-timers --all | grep warp-ai-watchdog
```

Expected healthy log patterns:

- `ok openai=1 gemini=1 ip=...`
- `recovered attempt=... openai=1 gemini=1 ip=...`

## Manual Commands

Run one health cycle immediately:

```bash
sudo /usr/local/bin/warp-ai-watchdog --run
```

Show the current WARP status:

```bash
warp-cli status
```

Check the current WARP-backed OpenAI trace:

```bash
curl --socks5-hostname 127.0.0.1:40000 \
  -fsS https://chat.openai.com/cdn-cgi/trace
```

Check Gemini with redirects and a cookie jar:

```bash
tmp_cookie="$(mktemp)"
curl --socks5-hostname 127.0.0.1:40000 \
  -A 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36' \
  -sS -L -c "$tmp_cookie" -b "$tmp_cookie" -D - -o /dev/null \
  https://gemini.google.com/
rm -f "$tmp_cookie"
```

## Troubleshooting

### The timer is active but nothing happens

- check `sudo journalctl -u warp-ai-watchdog.service -n 50 --no-pager`
- check `sudo tail -n 50 /var/log/warp-ai-watchdog.log`
- verify `warp-cli status`

### The watchdog keeps rotating without recovery

- confirm the SOCKS listener is actually WARP-backed
- confirm `warp-cli connect` changes connectivity on that host
- reduce assumptions: passing probes are service-specific and time-sensitive
- increase `MIN_CONSECUTIVE_FAILURES` if your environment is especially noisy

### I need a different check target

- keep the default logic unless you have a measured reason
- if you patch `OPENAI_URL` or `GEMINI_URL`, validate the semantics yourself

## Limitations

- A "healthy" result only means the current probes passed.
- Google or other AI services may still rate-limit specific sessions later.
- Some services behave differently in real browsers than in `curl`.
- If `warp-cli disconnect/connect` keeps returning the same poor IP, this tool
  cannot force Cloudflare to assign a better one.

## Safety Notes

- The watchdog uses a lock file to avoid concurrent runs.
- It never edits your WARP registration.
- It rotates connectivity only through:
  - `warp-cli disconnect`
  - `warp-cli connect`
  - `systemctl restart warp-svc`
- It stores transient cookies only under the configured state directory.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

MIT
