# Changelog

## 0.2.0

- Opt-in startup check of the upstream npm stable `latest` dist-tag (`RDC_AUTO_UPDATE=true`), with versioned persistent runtime cache and atomic selection after CLI validation.
- Offline, installation-failure and invalid-package fallback to last cached or image-bundled RDC; runtime changes do not require a new Docker build.
- Installer stores the choice, and `update.sh` preserves it across later image upgrades or accepts an explicit override.
- Documentation, offline/rollback guidance and unit/runtime validation added. Base image still bundles Desktop Commander 0.2.52.

## 0.1.0

- Independent public project for generic native-Linux host administration; no CyberController dependency.
- Self-contained, digest-pinned container base and lockfile-pinned Desktop Commander 0.2.52 runtime.
- Root-equivalent host access with explicit acknowledgement, host namespace helper, Docker CLI/plugins, Python, networking tools and Chromium.
- Dedicated persistent device/config/workspace volume; installation stopped by default.
- Managed installer, update with retained rollback container, uninstall and permission verification.
- Unit tests, explicit privileged lab smoke tests and commit-pinned CI/release workflows.
