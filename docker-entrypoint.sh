#!/usr/bin/env bash
set -euo pipefail
fail() { echo "ERROR: $*" >&2; exit 64; }
[[ "${RDC_ALLOW_HOST_ADMIN:-}" == true ]] || fail "Set RDC_ALLOW_HOST_ADMIN=true to acknowledge root-equivalent host access."
[[ "$(id -u)" == 0 ]] || fail "Host administration requires container UID 0."
[[ -S /var/run/docker.sock ]] || fail "Host Docker socket is missing."
mountpoint -q /host || fail "Host root must be mounted at /host."
[[ "$(stat -Lc '%d:%i' /host)" == "$(stat -Lc '%d:%i' /proc/1/root)" ]] || fail "PID 1 is not the mounted host; use --pid=host."
for d in /var/lib/rdc-host-admin /var/lib/rdc-host-admin/device /var/lib/rdc-host-admin/config /var/lib/rdc-host-admin/workspace; do
    mkdir -p "$d"
    chmod 0700 "$d"
done
# Explicitly unrestricted on first start. Preserve operator configuration thereafter.
# These app settings are not a security sandbox for a privileged container.
if [[ ! -e /root/.claude-server-commander/config.json ]]; then
    (umask 077; printf '%s\n' '{"allowedDirectories":[],"blockedCommands":[],"defaultShell":"/bin/bash"}' > /root/.claude-server-commander/config.json)
fi
echo "WARNING: RDC Host Admin can fully control this host. Stop the container to take this access path offline." >&2
exec "$@"
