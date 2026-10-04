# Changelog

## 0.1.0

- Independent public project for generic native-Linux host administration; no CyberController dependency.
- Self-contained, digest-pinned container base and lockfile-pinned Desktop Commander 0.2.52 runtime.
- Root-equivalent host access with explicit acknowledgement, host namespace helper, Docker CLI/plugins, Python, networking tools and Chromium.
- Dedicated persistent device/config/workspace volume; installation stopped by default.
- Managed installer, update with retained rollback container, uninstall and permission verification.
- Unit tests, explicit privileged lab smoke tests and commit-pinned CI/release workflows.
