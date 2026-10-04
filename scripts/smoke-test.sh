#!/usr/bin/env bash
# Only run on an authorized lab host. Changes are limited to uniquely named test resources.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/common.sh
source "$ROOT/scripts/common.sh"
[[ "${RDC_ALLOW_HOST_ADMIN:-}" == true ]] || fail 'Explicitly set RDC_ALLOW_HOST_ADMIN=true on an authorized lab host.'
require_docker
IMAGE=${1:-egori4/rdc-host-admin:0.1.0}
require_image "$IMAGE"
NAME="rdc-host-admin-smoke-$$"
STATE="${NAME}-state"
CHILD="${NAME}-child"
HOST_FILE=''
cleanup() {
    if [[ "$HOST_FILE" == /tmp/rdc-host-admin-smoke.* ]]; then
        docker exec "$NAME" hostsh rm -f -- "$HOST_FILE" >/dev/null 2>&1 || true
    fi
    docker rm -f "$CHILD" "$NAME" >/dev/null 2>&1 || true
    docker volume rm "$STATE" >/dev/null 2>&1 || true
}
trap cleanup EXIT
# Runtime must also fail closed when bypassing the installer.
set +e
docker run --rm --network none "$IMAGE" true > /tmp/"${NAME}-deny.log" 2>&1
status=$?
set -e
[[ "$status" -eq 64 ]] || fail "Runtime acknowledgement check returned $status, expected 64."
rm -f /tmp/"${NAME}-deny.log"
echo 'PASS: runtime refuses unacknowledged access'
docker volume create --label io.egori4.project=rdc-host-admin "$STATE" >/dev/null
launch() {
    docker run -d --name "$NAME" --hostname "$NAME" --user 0:0 \
        --label io.egori4.project=rdc-host-admin --label "io.egori4.state-volume=$STATE" \
        --privileged --pid=host --network=host --ipc=host --restart=no \
        --cpus 1 --memory 1024m --memory-swap 1024m --pids-limit 512 \
        --log-driver local --log-opt max-size=20m --log-opt max-file=3 \
        --mount type=bind,src=/,dst=/host,bind-propagation=rslave \
        --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
        --mount "type=volume,src=$STATE,dst=/var/lib/rdc-host-admin" \
        --env RDC_ALLOW_HOST_ADMIN=true "$IMAGE" sleep 300 >/dev/null
    sleep 2
    [[ "$(docker inspect "$NAME" --format '{{.State.Running}}')" == true ]] || {
        docker logs "$NAME"; fail 'Smoke container exited during startup.';
    }
}
launch
"$ROOT/scripts/verify-container.sh" "$NAME"
[[ "$(docker exec "$NAME" hostsh id -u)" == 0 ]]
[[ "$(docker exec "$NAME" hostsh hostname)" == "$(hostname)" ]]
value='literal with spaces; $(echo never-execute)'
[[ "$(docker exec "$NAME" hostsh printf '%s' "$value")" == "$value" ]]
echo 'PASS: host namespaces, root UID, hostname and exact argument handling'
HOST_FILE=$(docker exec "$NAME" hostsh mktemp /tmp/rdc-host-admin-smoke.XXXXXX)
docker exec "$NAME" hostsh sh -c 'printf "%s" host-admin-smoke > "$1"' sh "$HOST_FILE"
[[ "$(docker exec "$NAME" cat "/host$HOST_FILE")" == host-admin-smoke ]]
docker exec "$NAME" hostsh rm -f -- "$HOST_FILE"
HOST_FILE=''
echo 'PASS: create/read/delete only a temporary host file'
docker exec "$NAME" hostsh docker create --name "$CHILD" --network none \
    --label io.egori4.smoke-test=true --entrypoint sleep "$IMAGE" 30 >/dev/null
docker exec "$NAME" hostsh docker start "$CHILD" >/dev/null
docker exec "$NAME" hostsh docker stop "$CHILD" >/dev/null
docker exec "$NAME" hostsh docker rm "$CHILD" >/dev/null
echo 'PASS: host Docker create/start/stop/delete of an isolated test container'
docker exec "$NAME" sh -c 'node --version; python3 --version; docker --version; docker compose version; docker buildx version'
docker exec "$NAME" chromium --headless --no-sandbox --disable-gpu --dump-dom \
    'data:text/html,<h1>rdc-smoke-ok</h1>' 2>/dev/null | grep -q rdc-smoke-ok
echo 'PASS: bundled toolchain and real headless Chromium'
timeout 45 docker exec -i "$NAME" node --input-type=module < "$ROOT/scripts/smoke-mcp.mjs"
docker exec "$NAME" sh -c 'printf persistent > /workspace/smoke-marker'
config_before=$(docker exec "$NAME" sha256sum /root/.claude-server-commander/config.json)
docker restart "$NAME" >/dev/null
sleep 2
[[ "$(docker exec "$NAME" cat /workspace/smoke-marker)" == persistent ]]
docker rm -f "$NAME" >/dev/null
launch
[[ "$(docker exec "$NAME" cat /workspace/smoke-marker)" == persistent ]]
[[ "$(docker exec "$NAME" sha256sum /root/.claude-server-commander/config.json)" == "$config_before" ]]
echo 'PASS: workspace and settings persist across restart and container recreation'
docker stats --no-stream --format 'Smoke resources: CPU={{.CPUPerc}} RAM={{.MemUsage}}' "$NAME"
echo 'PASS: smoke tests complete; temporary resources will be removed'
