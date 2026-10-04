#!/usr/bin/env bash
# Shared operator preflights. Sourced by lifecycle scripts.
set -euo pipefail
PROJECT=rdc-host-admin
fail() { echo "ERROR: $*" >&2; exit 1; }
require_docker() {
    command -v docker >/dev/null 2>&1 || fail "Docker CLI is required."
    [[ "$(uname -s)" == Linux ]] || fail "Only native Linux Docker Engine is supported."
    local info endpoint
    info=$(docker info --format '{{.OSType}}|{{.OperatingSystem}}|{{json .SecurityOptions}}') || fail "Cannot access Docker Engine."
    [[ "$info" == linux\|* ]] || fail "A Linux Docker Engine is required."
    [[ "$info" != *rootless* && "$info" != *userns* && "$info" != *'Docker Desktop'* ]] || fail "Rootless, user-namespace remapping and Docker Desktop are not supported."
    if [[ -n "${DOCKER_CONTEXT:-}" ]]; then
        endpoint=$(docker context inspect "$DOCKER_CONTEXT" --format '{{.Endpoints.docker.Host}}')
    else
        endpoint=${DOCKER_HOST:-$(docker context inspect --format '{{.Endpoints.docker.Host}}')}
    fi
    [[ "$endpoint" == unix:///var/run/docker.sock || "$endpoint" == unix:///run/docker.sock ]] || fail "Use the target host's default local Docker socket, not a remote/custom Docker context."
}
require_ack() {
    if [[ "${RDC_ALLOW_HOST_ADMIN:-}" != true && -t 0 ]]; then
        local answer
        read -r -p 'This grants root-equivalent remote host access. Type HOST-ADMIN to continue: ' answer
        [[ "$answer" == HOST-ADMIN ]] && export RDC_ALLOW_HOST_ADMIN=true
    fi
    [[ "${RDC_ALLOW_HOST_ADMIN:-}" == true ]] || fail "Set RDC_ALLOW_HOST_ADMIN=true after reviewing docs/SECURITY.md."
}
validate_name() {
    [[ "$2" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || fail "Invalid $1: use letters, numbers, dot, underscore, and hyphen."
}
require_image() {
    local image=$1 role
    if ! docker image inspect "$image" >/dev/null 2>&1; then docker pull "$image"; fi
    role=$(docker image inspect "$image" --format '{{index .Config.Labels "io.egori4.security-profile"}}')
    [[ "$role" == host-admin ]] || fail "Image is not labeled as an RDC host-admin image: $image"
}
require_managed() {
    local name=$1 project
    project=$(docker container inspect "$name" --format '{{index .Config.Labels "io.egori4.project"}}') || fail "Container not found: $name"
    [[ "$project" == "$PROJECT" ]] || fail "Refusing to modify a container not managed by this project: $name"
}
