# Deployment and operations

## 1. Prerequisites and trust

Use a native Linux machine with rootful Docker Engine, a Docker CLI connected to the default local Docker socket, and Bash. The image supplies Node/npm, RDC and administration tools; Git is only needed if you choose to clone rather than download/extract a source release.

Run the installer on the target host. It refuses unsupported/remote Docker contexts. Confirm that the Desktop Commander account receiving the new device is allowed to administer the **entire** machine. This container cannot enforce per-directory or read-only host restrictions.

Outbound Internet connectivity is required by Desktop Commander Remote. Installing an image offline does not make the remote service an offline/on-premises service. No existing application port (including 443) needs to be freed.

## 2. Install

```bash
git clone https://github.com/egori4/rdc-host-admin.git
cd rdc-host-admin
./install.sh
```

The script asks for the `HOST-ADMIN` acknowledgement and a device name. It refuses to replace any existing container and refuses to reuse a volume belonging to another project.

Noninteractive example:

```bash
RDC_ALLOW_HOST_ADMIN=true RDC_DEVICE_NAME=lab01-host-admin START_NOW=n ./install.sh
```

The default container remains stopped. `START_NOW=y` explicitly starts it detached. The acknowledgement is an accident-prevention measure, not protection against someone who already controls Docker.

Only these host Docker objects are created by a fresh install:

- container `rdc-host-admin`
- volume `rdc-host-admin-state`

The named volume contains `device/` (pairing), `config/` (RDC settings) and `workspace/` (persistent working files). In-container paths are `/root/.desktop-commander-device`, `/root/.claude-server-commander`, and `/workspace`. Treat the entire volume as sensitive. Runtime files elsewhere in the container are disposable.

## 3. Pair the intended account

```bash
docker start -ai rdc-host-admin
```

Open the displayed verification URL in your browser and approve this device in the intended Desktop Commander account. Do not approve an unfamiliar pairing request. Pairing codes and device-state files are credentials; do not put them in Git, issues or screenshots of public logs.

After pairing, detach using Docker's detach mechanism where available, or stop with Ctrl+C and start detached:

```bash
docker start rdc-host-admin
```

Future starts reuse the saved identity. A second copy must not use the same state volume concurrently. Normal shell commands run inside the container, not automatically on the host; use `/host` with file tools or `hostsh` with host commands.

## 4. Verify

```bash
./scripts/verify-container.sh rdc-host-admin
docker exec rdc-host-admin hostsh id
docker exec rdc-host-admin hostsh hostname
docker exec rdc-host-admin hostsh docker ps
docker stats --no-stream rdc-host-admin
```

This verifies configured permissions and direct host access, not successful remote-account authorization. Check the device in Desktop Commander and perform a read-only call through the remote session separately.

## 5. Stop, restart and reboot policy

```bash
docker stop rdc-host-admin       # take this remote-access path offline
docker start rdc-host-admin      # reuse existing pairing
```

Default restart policy is `no`: a host reboot does not automatically restore this privileged access path. Persistent service operation is an explicit choice:

```bash
docker update --restart unless-stopped rdc-host-admin
```

Or set `RDC_RESTART_POLICY=unless-stopped` at install. Stopping RDC does not revoke an independent service/session another administrator may have created on the host. Do not reboot production services merely to test this container.

## 6. Accounts and credentials

There is one RDC device identity per state volume, and **no Evidence MCP bearer token** in this project. Alice and Bob need separate container names, device names and state volumes:

```bash
RDC_ALLOW_HOST_ADMIN=true CONTAINER_NAME=rdc-host-admin-alice STATE_VOLUME=rdc-host-admin-alice-state RDC_DEVICE_NAME=lab01-admin-alice ./install.sh

RDC_ALLOW_HOST_ADMIN=true CONTAINER_NAME=rdc-host-admin-bob STATE_VOLUME=rdc-host-admin-bob-state RDC_DEVICE_NAME=lab01-admin-bob ./install.sh
```

Pair each in the matching account. Both have root-equivalent access to the same host; separate identities are **not** tenant isolation, and one host administrator can read the other's local state.

Never reuse or copy the restricted CyberController client's pairing state into this container. A privileged device should have its own explicit authorization and recognizable name.

## 7. Upgrade

Review the new release and use an exact version or digest:

```bash
docker pull egori4/rdc-host-admin:<version>
RDC_ALLOW_HOST_ADMIN=true ./update.sh egori4/rdc-host-admin:<version>
```

`update.sh` validates the new image's role label before stopping anything. It preserves device name, state volume, CPU/RAM/PID settings, restart policy and running/stopped state. The old container is renamed to a timestamped `rdc-host-admin-rollback-...` name and kept stopped. If replacement creation or the immediate process-start check fails, it restores the old container automatically.

The short process check is not an end-to-end remote connectivity check. Verify the remote session yourself. Do not start both old and new containers; they share identity/configuration. These managed lifecycle scripts do not preserve arbitrary manual mounts or customizations outside the documented installer settings.

Manual rollback (substitute the exact backup name printed by the updater):

```bash
docker stop rdc-host-admin
docker rm rdc-host-admin
docker rename rdc-host-admin-rollback-<timestamp> rdc-host-admin
docker start rdc-host-admin
```

After confirming the new release, remove the stopped backup container with `docker rm <backup-name>`. Never remove the state volume as part of a normal image update. State written by future upstream versions may require a separate backup to roll back across incompatible schema changes.

## 8. Back up state

Stop the container before making a backup. The archive contains a live device credential and may contain confidential working files; store it securely, outside this repository.

```bash
docker stop rdc-host-admin
umask 077
docker run --rm --network none   --mount type=volume,src=rdc-host-admin-state,dst=/state,readonly   --entrypoint tar egori4/rdc-host-admin:0.1.0 -C /state -czf - . > /secure/path/rdc-state.tar.gz
```

Restart only after the backup is complete. Restoring a backup must not create two active copies of one identity. Prefer fresh pairing when moving to a different trust environment.

## 9. Revoke, change accounts, or uninstall

Immediately take access offline with `docker stop rdc-host-admin`. Permanently revoke the device in Desktop Commander's account/device-management interface. Local removal alone is not server-side revocation.

Remove the managed container but retain local pairing/configuration/workspace:

```bash
./uninstall.sh
```

Delete all of that state as well (irreversible):

```bash
./uninstall.sh --purge-state
```

The purge asks for `DELETE`. For explicitly noninteractive removal use `RDC_PURGE_STATE=true`. Remove any stopped rollback containers first; Docker refuses to delete a volume still referenced by one. Use `CONTAINER_NAME=<custom-name>` for nondefault installations.

To change RDC accounts, revoke the old device, remove its container/state, reinstall with a fresh state volume, and pair the new account. Do not edit saved device credential JSON by hand.

## 10. Offline image transfer

On a connected machine:

```bash
docker pull egori4/rdc-host-admin:0.1.0
docker save egori4/rdc-host-admin:0.1.0 | gzip > rdc-host-admin-0.1.0.tar.gz
```

Transfer the image archive and the tagged source/installer bundle using an approved channel. On the target:

```bash
gunzip -c rdc-host-admin-0.1.0.tar.gz | docker load
./install.sh
```

The installer uses a matching local image without pulling it again. Runtime remote pairing/connectivity still requires outbound Internet access. This supports separate labs without direct connectivity between them.

## 11. Resource settings and limitations

Install overrides: `RDC_CPUS`, `RDC_MEMORY`, `RDC_PIDS_LIMIT`, `RDC_RESTART_POLICY`, `RDC_HOST_ADMIN_IMAGE`, `CONTAINER_NAME`, `STATE_VOLUME`, `RDC_DEVICE_NAME`, `START_NOW`.

The normal image is larger than the restricted client because it includes a real browser and administration tools. Memory-intensive browser or data jobs can need more than the default 1 GiB. Host-administration operations launched through Docker or host services may run outside these resource limits. RDC's own persistent workspace/log files are not governed by the Docker stdout log-rotation limit.

No SELinux host-root relabeling is performed: never add `:Z` or `:z` to the host `/` mount. Hosts with additional mandatory-access policies require their own review. Do not disable unrelated platform security globally to make an installation work.
