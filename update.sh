#!/usr/bin/env bash
# Replace only this project's container; retain a stopped rollback container.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
source "$ROOT/scripts/common.sh"
IMAGE=${1:-}
[[ -n "$IMAGE" && $# -eq 1 ]] || fail "Usage: RDC_ALLOW_HOST_ADMIN=true ./update.sh <image:version-or-digest>"
NAME=${CONTAINER_NAME:-rdc-host-admin}
require_ack
require_docker
validate_name CONTAINER_NAME "$NAME"
require_managed "$NAME"
require_image "$IMAGE"
STATE=$(docker inspect "$NAME" --format '{{index .Config.Labels "io.egori4.state-volume"}}')
DEVICE=$(docker inspect "$NAME" --format '{{.Config.Hostname}}')
CPUS=$(docker inspect "$NAME" --format '{{.HostConfig.NanoCpus}}')
CPUS=$(awk -v n="$CPUS" 'BEGIN {printf "%.9f", n/1000000000}')
MEMORY=$(docker inspect "$NAME" --format '{{.HostConfig.Memory}}')
PIDS=$(docker inspect "$NAME" --format '{{.HostConfig.PidsLimit}}')
RESTART=$(docker inspect "$NAME" --format '{{.HostConfig.RestartPolicy.Name}}')
RUNNING=$(docker inspect "$NAME" --format '{{.State.Running}}')
BACKUP="${NAME}-rollback-$(date -u +%Y%m%dT%H%M%SZ)"
if docker container inspect "$BACKUP" >/dev/null 2>&1; then fail "Rollback container already exists: $BACKUP"; fi
[[ "$RUNNING" != true ]] || docker stop "$NAME" >/dev/null
docker rename "$NAME" "$BACKUP"
rollback() {
    local status=$?
    trap - ERR INT TERM
    echo "Update failed; restoring $BACKUP to $NAME." >&2
    if docker container inspect "$NAME" >/dev/null 2>&1; then
        owner=$(docker inspect "$NAME" --format '{{index .Config.Labels "io.egori4.state-volume"}}')
        if [[ "$owner" != "$STATE" ]]; then
            echo "Refusing to remove an unrelated concurrent container; recover $BACKUP manually." >&2
            exit 1
        fi
        docker rm -f "$NAME" >/dev/null
    fi
    docker rename "$BACKUP" "$NAME"
    if [[ "$RUNNING" == true ]]; then docker start "$NAME" >/dev/null; fi
    [[ "$status" -ne 0 ]] || status=1
    exit "$status"
}
trap rollback ERR INT TERM
RDC_ALLOW_HOST_ADMIN=true RDC_HOST_ADMIN_IMAGE="$IMAGE" CONTAINER_NAME="$NAME"     STATE_VOLUME="$STATE" RDC_DEVICE_NAME="$DEVICE" RDC_CPUS="$CPUS" RDC_MEMORY="$MEMORY"     RDC_PIDS_LIMIT="$PIDS" RDC_RESTART_POLICY="$RESTART" START_NOW=n "$ROOT/install.sh"
if [[ "$RUNNING" == true ]]; then
    docker start "$NAME" >/dev/null
    sleep 3
    [[ "$(docker inspect "$NAME" --format '{{.State.Running}}')" == true ]]
fi
trap - ERR INT TERM
printf 'Updated %s. Stopped rollback container retained: %s\n' "$NAME" "$BACKUP"
echo 'Do not start both containers: they share one device identity and state volume.'
echo 'Local process startup was checked; verify the remote connection separately.'
