# Contributing

## Scope

This project is intentionally narrow:

- local watchdog logic
- installation and operational safety
- practical service probes

Please avoid turning it into a generic proxy manager or a panel integration
layer.

## Development Rules

- keep changes small and reviewable
- prefer bash portability over clever shell tricks
- document new environment variables in both `README.md` and
  `warp-ai-watchdog.env.example`
- keep the default behavior safe for root-operated Linux hosts

## Local Validation

Run the minimum checks before opening a pull request:

```bash
bash -n warp-ai-watchdog.sh install.sh uninstall.sh
./warp-ai-watchdog.sh --help
./install.sh --help
./uninstall.sh --help
git diff --check
```

If you change systemd units, explain the operational impact in the pull request.

## Pull Requests

Include:

- what changed
- why the change is needed
- how you validated it
- any operator-facing behavior change

## Security

Do not include:

- private IPs
- hostnames tied to a private deployment
- tokens, cookies, or credentials
- logs with sensitive operational context

See [`SECURITY.md`](SECURITY.md) for reporting guidance.
