#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
source "$ROOT/scripts/common.sh"
IMAGE=${RDC_HOST_ADMIN_IMAGE:-egori4/rdc-host-admin:0.1.0}
NAME=${CONTAINER_NAME:-rdc-host-admin}
STATE=${STATE_VOLUME:-rdc-host-admin-state}
DEVICE=${RDC_DEVICE_NAME:-}
CPUS=${RDC_CPUS:-1.0}
MEMORY=${RDC_MEMORY:-1024m}
PIDS=${RDC_PIDS_LIMIT:-512}
RESTART=${RDC_RESTART_POLICY:-no}
require_ack
require_docker
validate_name CONTAINER_NAME "$NAME"
validate_name STATE_VOLUME "$STATE"
[[ "$RESTART" == no || "$RESTART" == unless-stopped ]] || fail "RDC_RESTART_POLICY must be no or unless-stopped."
if [[ -z "$DEVICE" ]]; then
    default="host-admin-$(hostname -s)"
    if [[ -t 0 ]]; then read -r -p "RDC device name [$default]: " DEVICE; fi
    DEVICE=${DEVICE:-$default}
fi
[[ "$DEVICE" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ && ${#DEVICE} -le 63 ]] || fail "RDC_DEVICE_NAME must be a DNS-style hostname, at most 63 characters."
if docker container inspect "$NAME" >/dev/null 2>&1; then
    fail "Container $NAME already exists. Use update.sh; nothing was removed."
fi
require_image "$IMAGE"
if docker volume inspect "$STATE" >/dev/null 2>&1; then
    owner=$(docker volume inspect "$STATE" --format '{{index .Labels "io.egori4.project"}}')
    [[ "$owner" == "$PROJECT" ]] || fail "Refusing to use an unrelated state volume: $STATE"
else
    docker volume create --label "io.egori4.project=$PROJECT" "$STATE" >/dev/null
fi
docker create \
    --name "$NAME" --hostname "$DEVICE" --user 0:0 \
    --label "io.egori4.project=$PROJECT" --label "io.egori4.state-volume=$STATE" \
    --privileged --pid=host --network=host --ipc=host \
    --restart "$RESTART" --stop-timeout 20 \
    --cpus "$CPUS" --memory "$MEMORY" --memory-swap "$MEMORY" --pids-limit "$PIDS" \
    --log-driver local --log-opt max-size=20m --log-opt max-file=3 \
    --tmpfs /tmp:rw,nosuid,nodev,size=256m \
    --mount type=bind,src=/,dst=/host,bind-propagation=rslave \
    --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
    --mount "type=volume,src=$STATE,dst=/var/lib/rdc-host-admin" \
    --env RDC_ALLOW_HOST_ADMIN=true \
    "$IMAGE" >/dev/null
printf 'Created STOPPED host-admin container: %s\nRDC device name: %s\nState volume: %s\n' "$NAME" "$DEVICE" "$STATE"
printf 'Pair: docker start -ai %s\nOffline: docker stop %s\nVerify: ./scripts/verify-container.sh %s\n' "$NAME" "$NAME" "$NAME"
if [[ "${START_NOW:-n}" == y ]]; then
    docker start "$NAME" >/dev/null
    echo "Started. View browser pairing URL with: docker logs -f $NAME"
fi
