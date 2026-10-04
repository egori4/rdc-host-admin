#!/usr/bin/env bash
# Explicit lab test of installation, successful update, failed-update rollback and purge.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/common.sh
source "$ROOT/scripts/common.sh"
[[ "${RDC_ALLOW_HOST_ADMIN:-}" == true ]] || fail 'Explicit lab host-administration acknowledgement is required.'
require_docker
IMAGE=${1:-egori4/rdc-host-admin:0.1.0}
require_image "$IMAGE"
NAME="rdc-host-admin-lifecycle-$$"
STATE="${NAME}-state"
GOOD="${NAME}:good"
BAD="${NAME}:bad"
export CONTAINER_NAME="$NAME" STATE_VOLUME="$STATE" RDC_DEVICE_NAME="$NAME" START_NOW=n
cleanup() {
    local id
    while read -r id; do
        [[ -z "$id" ]] || docker rm -f "$id" >/dev/null 2>&1 || true
    done < <(docker ps -aq --filter "label=io.egori4.state-volume=$STATE")
    docker volume rm "$STATE" >/dev/null 2>&1 || true
    docker image rm "$GOOD" "$BAD" >/dev/null 2>&1 || true
}
trap cleanup EXIT
# Test variants inherit the exact production image; neither opens a remote pairing session.
printf 'FROM %s\nCMD ["sleep", "300"]\n' "$IMAGE" | docker build -q -t "$GOOD" - >/dev/null
printf 'FROM %s\nENTRYPOINT ["/bin/false"]\n' "$IMAGE" | docker build -q -t "$BAD" - >/dev/null
RDC_HOST_ADMIN_IMAGE="$GOOD" "$ROOT/install.sh"
[[ "$(docker inspect "$NAME" --format '{{.State.Status}}')" == created ]]
docker start "$NAME" >/dev/null
sleep 2
docker exec "$NAME" sh -c 'printf kept > /workspace/lifecycle-marker'
"$ROOT/update.sh" "$GOOD"
[[ "$(docker inspect "$NAME" --format '{{.State.Running}}')" == true ]]
[[ "$(docker exec "$NAME" cat /workspace/lifecycle-marker)" == kept ]]
echo 'PASS: installer is stopped by default; successful update preserves running state and data'
sleep 1
if "$ROOT/update.sh" "$BAD"; then fail 'Intentionally broken image should have triggered rollback.'; fi
[[ "$(docker inspect "$NAME" --format '{{.State.Running}}')" == true ]]
[[ "$(docker inspect "$NAME" --format '{{.Config.Image}}')" == "$GOOD" ]]
[[ "$(docker exec "$NAME" cat /workspace/lifecycle-marker)" == kept ]]
echo 'PASS: failed startup automatically rolls back to the working image and state'
"$ROOT/uninstall.sh"
docker volume inspect "$STATE" >/dev/null
while read -r id; do
    [[ -z "$id" ]] || docker rm -f "$id" >/dev/null
done < <(docker ps -aq --filter "label=io.egori4.state-volume=$STATE")
RDC_HOST_ADMIN_IMAGE="$GOOD" "$ROOT/install.sh"
docker start "$NAME" >/dev/null
sleep 2
[[ "$(docker exec "$NAME" cat /workspace/lifecycle-marker)" == kept ]]
RDC_PURGE_STATE=true "$ROOT/uninstall.sh" --purge-state
if docker volume inspect "$STATE" >/dev/null 2>&1; then fail 'Test state volume was not removed.'; fi
echo 'PASS: uninstall preserves state by default; explicit purge deletes only the test state'
