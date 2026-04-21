# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Changed

- added staged healing so the watchdog only restarts `warp-svc` when the
  service or SOCKS listener is still unhealthy after a reconnect attempt
- added transient recheck plus consecutive-failure gating to reduce unnecessary
  WARP session churn from one-off probe failures
- added `MIN_CONSECUTIVE_FAILURES` and `VERIFY_RECHECK_DELAY` configuration
  knobs for noisy environments

## [0.1.0] - 2026-04-20

### Added

- initial public release of `warp-ai-watchdog`
- WARP reconnect loop with OpenAI and Gemini health probes
- systemd service and timer installation flow
- example environment file for operator-friendly customization
- contribution guide
- GitHub issue templates
- GitHub Actions shell validation workflow
- README sections for verification and troubleshooting

### Changed

- fixed SOCKS argument handling in the main watchdog script
- added a configurable browser-like `USER_AGENT` for Gemini probing
- added help output for install and uninstall scripts
- made the main health path pass `ShellCheck` cleanly
