#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/common.sh
source "$ROOT/scripts/common.sh"
NAME=${1:-rdc-host-admin}
require_docker
require_managed "$NAME"
errors=0
check() {
    local label=$1 expression=$2 expected=$3 actual
    actual=$(docker inspect "$NAME" --format "$expression")
    if [[ "$actual" == "$expected" ]]; then echo "PASS: $label"; else echo "FAIL: $label ($actual != $expected)"; errors=$((errors+1)); fi
}
check 'privileged host administration' '{{.HostConfig.Privileged}}' true
check 'host PID namespace' '{{.HostConfig.PidMode}}' host
check 'host networking' '{{.HostConfig.NetworkMode}}' host
check 'host IPC namespace' '{{.HostConfig.IpcMode}}' host
check 'private UTS for a separate RDC display name' '{{.HostConfig.UTSMode}}' ''
check 'root container user' '{{.Config.User}}' '0:0'
check 'read-write host root mount' '{{range .Mounts}}{{if eq .Destination "/host"}}{{.Source}}:{{.RW}}{{end}}{{end}}' '/:true'
check 'host Docker socket' '{{range .Mounts}}{{if eq .Destination "/var/run/docker.sock"}}{{.Source}}{{end}}{{end}}' '/var/run/docker.sock'
check 'persistent state volume' '{{range .Mounts}}{{if eq .Destination "/var/lib/rdc-host-admin"}}{{.Type}}{{end}}{{end}}' volume
check 'bounded Docker log driver' '{{.HostConfig.LogConfig.Type}}' local
printf '\nConfigured resources and restart policy:\n'
docker inspect "$NAME" --format 'CPU(nano)={{.HostConfig.NanoCpus}} RAM={{.HostConfig.Memory}} Swap={{.HostConfig.MemorySwap}} PIDs={{.HostConfig.PidsLimit}} Restart={{.HostConfig.RestartPolicy.Name}}'
echo 'These are operational checks, NOT a security boundary against a privileged administrator.'
[[ "$errors" -eq 0 ]]
