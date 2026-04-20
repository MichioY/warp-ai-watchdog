# Security Policy

## Scope

This project is a local watchdog for WARP-based AI routing.

It does not ship credentials, private endpoints, or remote execution features.

## Safe Usage

- Review `install.sh` before running it as root.
- Review `/etc/default/warp-ai-watchdog` after installation.
- Do not commit private IPs, tokens, cookies, or host-specific configs.
- Keep the watchdog log local unless you have removed sensitive context.

## What The Project Does

- runs local probe requests through a SOCKS proxy
- reads probe results
- reconnects WARP with `warp-cli`
- restarts `warp-svc`
- logs health transitions

## What The Project Does Not Do

- upload telemetry
- modify WARP registration
- exfiltrate cookies or secrets
- guarantee a "clean" exit IP

## Reporting

If you find a security issue in the open-source code, open a private report or
publish a minimal reproduction that does not include private operational data.
