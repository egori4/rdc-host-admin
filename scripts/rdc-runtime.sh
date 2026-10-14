#!/usr/bin/env bash
# Opt-in Desktop Commander runtime updates. The container image remains immutable.
set -euo pipefail

PACKAGE='@wonderwhy-er/desktop-commander'
STATE_DIR=${RDC_STATE_DIR:-/var/lib/rdc-host-admin}
BUNDLED_DIR=${RDC_BUNDLED_DIR:-/opt/rdc}
BUNDLED_BIN="$BUNDLED_DIR/node_modules/.bin/desktop-commander"
BUNDLED_META="$BUNDLED_DIR/node_modules/@wonderwhy-er/desktop-commander/package.json"
CACHE_DIR="$STATE_DIR/runtime"
VERSIONS_DIR="$CACHE_DIR/versions"
SELECTED_FILE="$CACHE_DIR/selected-version"

log() { printf 'RDC runtime: %s\n' "$*" >&2; }
stable_version() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }
version_newer() {
    [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" == "$1" ]]
}
package_version() {
    node -p 'require(process.argv[1]).version' "$1" 2>/dev/null
}
runtime_valid() {
    local dir=$1 version=$2
    local bin="$dir/node_modules/.bin/desktop-commander"
    local meta="$dir/node_modules/@wonderwhy-er/desktop-commander/package.json"
    [[ -x "$bin" && -f "$meta" ]] &&
        [[ "$(package_version "$meta")" == "$version" ]] &&
        timeout 15s "$bin" remote --help >/dev/null 2>&1
}

[[ -x "$BUNDLED_BIN" ]] || { log "Bundled runtime missing"; exit 1; }
bundled_version=$(package_version "$BUNDLED_META")
stable_version "$bundled_version" || { log "Invalid bundled version"; exit 1; }

case "${RDC_AUTO_UPDATE:-false}" in
    false)
        log "using bundled $bundled_version (automatic updates disabled)"
        exec "$BUNDLED_BIN" "$@"
        ;;
    true) ;;
    *) log "RDC_AUTO_UPDATE must be true or false"; exit 64 ;;
esac

if ! mkdir -p "$VERSIONS_DIR" || ! chmod 0700 "$CACHE_DIR" "$VERSIONS_DIR"; then
    log "persistent cache unavailable; starting bundled $bundled_version"
    exec "$BUNDLED_BIN" "$@"
fi

active_version=$bundled_version
active_bin=$BUNDLED_BIN
if [[ -f "$SELECTED_FILE" ]]; then
    read -r saved_version < "$SELECTED_FILE" || saved_version=
    if stable_version "$saved_version" && version_newer "$saved_version" "$bundled_version" &&
       runtime_valid "$VERSIONS_DIR/$saved_version" "$saved_version"; then
        active_version=$saved_version
        active_bin="$VERSIONS_DIR/$saved_version/node_modules/.bin/desktop-commander"
    else
        log "saved runtime is unavailable or older than bundled; falling back to $bundled_version"
    fi
fi

# The npm 'latest' dist-tag is the stable channel. Reject prerelease/malformed versions.
if latest=$(timeout 12s npm view "$PACKAGE" dist-tags.latest --fetch-retries=0 --fetch-timeout=9000 2>/dev/null); then
    latest=$(printf '%s' "$latest" | tr -d '\r\n')
    if ! stable_version "$latest"; then
        log "registry returned a non-stable version; retaining $active_version"
    elif version_newer "$latest" "$active_version"; then
        if runtime_valid "$VERSIONS_DIR/$latest" "$latest"; then
            candidate=true
        else
            candidate=false
            # Do not replace the selected working installation until fully validated.
            if staging=$(mktemp -d "$VERSIONS_DIR/.install.XXXXXXXX"); then
                log "installing $latest into persistent cache"
                if timeout 180s npm install --prefix "$staging" --no-save --no-package-lock \
                       --no-audit --no-fund --omit=dev "$PACKAGE@$latest" >/dev/null 2>&1 &&
                   runtime_valid "$staging" "$latest" &&
                   rm -rf -- "$VERSIONS_DIR/$latest" &&
                   mv -- "$staging" "$VERSIONS_DIR/$latest"; then
                    candidate=true
                else
                    log "installation/validation of $latest failed; retaining $active_version"
                    rm -rf -- "$staging" || true
                fi
            else
                log "cannot create runtime cache; retaining $active_version"
            fi
        fi
        if [[ "$candidate" == true ]]; then
            if marker=$(mktemp "$CACHE_DIR/.selected.XXXXXXXX"); then
                if printf '%s\n' "$latest" > "$marker" && mv -f -- "$marker" "$SELECTED_FILE"; then
                    active_version=$latest
                    active_bin="$VERSIONS_DIR/$latest/node_modules/.bin/desktop-commander"
                    log "activated $latest"
                else
                    rm -f -- "$marker" || true
                    log "could not save runtime selection; retaining $active_version"
                fi
            else
                log "cannot write runtime selection; retaining $active_version"
            fi
        fi
    fi
else
    log "registry unavailable; retaining $active_version"
fi

log "starting $active_version"
exec "$active_bin" "$@"
