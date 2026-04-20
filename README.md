# warp-ai-watchdog

`warp-ai-watchdog` is a small watchdog for WARP-based AI routing.

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

## Repository Layout

- `warp-ai-watchdog.sh`
  - main watchdog script
- `install.sh`
  - installs the script, config file, and systemd units
- `uninstall.sh`
  - removes the installed components
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

After install:

```bash
sudo systemctl status warp-ai-watchdog.timer
sudo systemctl start warp-ai-watchdog.service
sudo tail -f /var/log/warp-ai-watchdog.log
```

## Configuration

The installer writes:

```bash
/etc/default/warp-ai-watchdog
```

Supported settings:

```bash
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
CHECK_INTERVAL_MINUTES=5
LOG_FILE=/var/log/warp-ai-watchdog.log
STATE_DIR=/var/lib/warp-ai-watchdog
```

After editing the config:

```bash
sudo systemctl daemon-reload
sudo systemctl restart warp-ai-watchdog.timer
sudo systemctl start warp-ai-watchdog.service
```

## Health Logic

The watchdog uses this decision model:

1. Probe OpenAI through WARP.
2. Probe Gemini through WARP using redirects plus a cookie jar.
3. If both are healthy, exit cleanly.
4. If either is degraded:
   - disconnect WARP
   - reconnect WARP
   - restart `warp-svc`
   - compare the current exit IP against the previous one
   - probe again
5. Stop after `MAX_ATTEMPTS`.

This means the watchdog does not look for a theoretically "clean" IP. It looks
for an IP that passes the actual site probes now.

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

## License

MIT
