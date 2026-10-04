#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
source "$ROOT/scripts/common.sh"
PURGE=false
if [[ $# -eq 1 && "$1" == --purge-state ]]; then PURGE=true; elif [[ $# -gt 0 ]]; then fail 'Usage: ./uninstall.sh [--purge-state]'; fi
NAME=${CONTAINER_NAME:-rdc-host-admin}
require_docker
require_managed "$NAME"
STATE=$(docker inspect "$NAME" --format '{{index .Config.Labels "io.egori4.state-volume"}}')
if [[ "$PURGE" == true ]]; then
    if [[ "${RDC_PURGE_STATE:-}" != true && -t 0 ]]; then
        read -r -p "Delete pairing, configuration and workspace in $STATE? Type DELETE: " answer
        [[ "$answer" == DELETE ]] && RDC_PURGE_STATE=true
    fi
    [[ "${RDC_PURGE_STATE:-}" == true ]] || fail 'State deletion requires RDC_PURGE_STATE=true or interactive confirmation.'
    owner=$(docker volume inspect "$STATE" --format '{{index .Labels "io.egori4.project"}}')
    [[ "$owner" == "$PROJECT" ]] || fail 'Refusing to delete an unrelated volume.'
fi
docker rm -f "$NAME" >/dev/null
if [[ "$PURGE" == true ]]; then
    docker volume rm "$STATE"
else
    echo "Preserved state volume: $STATE"
fi
echo 'Also revoke the device in the Desktop Commander account for permanent server-side revocation.'
