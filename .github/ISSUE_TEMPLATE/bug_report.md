---
name: Bug report
about: Report a concrete defect in watchdog behavior
title: "[bug] "
labels: bug
assignees: ""
---

## Summary

Describe the observable problem.

## Environment

- Linux distribution:
- systemd version:
- WARP client version:
- `warp-cli status` summary:

## Expected Behavior

Describe what should have happened.

## Actual Behavior

Describe what actually happened.

## Validation

Share only redacted output from:

```bash
sudo tail -n 50 /var/log/warp-ai-watchdog.log
sudo systemctl status warp-ai-watchdog.service --no-pager
```

## Notes

Do not paste credentials, private IPs, or full unredacted logs.
