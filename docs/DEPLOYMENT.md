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

The named volume contains `device/` (pairing), `config/` (RDC settings), `workspace/` (persistent files) and, when auto-update is enabled, `runtime/` (downloaded runtime versions and the selected version). In-container paths are `/root/.desktop-commander-device`, `/root/.claude-server-commander`, and `/workspace`. Treat the entire volume as sensitive. Runtime files elsewhere in the container are disposable.

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

Default restart policy is `no`: a Docker daemon restart or host reboot intentionally takes this root-equivalent remote-access path offline. This is the recommended security posture. Bring it back only through an explicit local/approved administrative action:

```bash
docker start rdc-host-admin
```

The persistent state volume retains the paired device identity, so an intentional restart can reuse the existing pairing. Do not change the container to an automatic restart policy merely for convenience or monitoring availability; doing so turns a break-glass administrative path into a persistent remote-management service. If an environment has an explicitly approved requirement for persistent host-admin access, review that as a separate security decision before setting `RDC_RESTART_POLICY=unless-stopped`.

Stopping RDC does not revoke an independent service/session another administrator may have created on the host. Do not reboot production services merely to test this container.

## 6. Accounts and credentials

There is one RDC device identity per state volume, and **no Evidence MCP bearer token** in this project. Alice and Bob need separate container names, device names and state volumes:

```bash
RDC_ALLOW_HOST_ADMIN=true CONTAINER_NAME=rdc-host-admin-alice STATE_VOLUME=rdc-host-admin-alice-state RDC_DEVICE_NAME=lab01-admin-alice ./install.sh

RDC_ALLOW_HOST_ADMIN=true CONTAINER_NAME=rdc-host-admin-bob STATE_VOLUME=rdc-host-admin-bob-state RDC_DEVICE_NAME=lab01-admin-bob ./install.sh
```

Pair each in the matching account. Both have root-equivalent access to the same host; separate identities are **not** tenant isolation, and one host administrator can read the other's local state.

Never reuse or copy the restricted CyberController client's pairing state into this container. A privileged device should have its own explicit authorization and recognizable name.

## 7. Upgrade

### A. Update Desktop Commander without changing the image (v0.2.0+)

**Off by default.** For a new deployment, include `RDC_AUTO_UPDATE=true` when invoking `install.sh`. To migrate an existing **0.1.0** host-admin container to the 0.2.0 image and enable it, perform the following **on the host via SSH or another independent administrative session**, not via the RDC connection that will be restarted:

```bash
cd /opt/radware/storage/scripts/rdc-host-admin
git pull --ff-only origin main
docker pull egori4/rdc-host-admin:0.2.0
RDC_ALLOW_HOST_ADMIN=true RDC_AUTO_UPDATE=true ./update.sh egori4/rdc-host-admin:0.2.0
docker logs --tail 30 rdc-host-admin
```

The updater preserves the `rdc-host-admin-state` volume, device hostname/pairing, other Docker settings and running/stopped state. It retains the previous container, stopped, with a timestamped rollback name. It also preserves `RDC_AUTO_UPDATE` on **later image upgrades**, unless an explicit `RDC_AUTO_UPDATE=true|false` is supplied when running `update.sh`. A legacy container lacking this setting defaults to `false`; upgrading its image alone does not silently enable network-fetched code.

On each **explicit start/restart**, if enabled, the startup script checks `@wonderwhy-er/desktop-commander` via the npm `latest` dist-tag (12-second query limit; only numeric stable versions). For a newer version, it downloads packages into a temporary directory in the persistent state volume (180-second limit), verifies installed metadata and that `desktop-commander remote --help` works (15-second limit), then atomically selects it. The image-bundled fallback is 0.2.52; an already validated cached release is preferred when newer than the fallback. Registry outages, invalid version responses, bad downloads or failed validation do not block startup. No polling, surprise restart or periodic background update occurs while running.

**Check which runtime started:**

```bash
docker logs --tail 40 rdc-host-admin
docker inspect rdc-host-admin --format '{{.Config.Image}}'
docker inspect rdc-host-admin --format '{{range .Config.Env}}{{println .}}{{end}}' | grep RDC_AUTO_UPDATE
# Optional: if a cached runtime was selected
docker exec rdc-host-admin cat /var/lib/rdc-host-admin/runtime/selected-version
```

The selected-version file does not exist when no cached runtime was activated. Container image tags and `docker inspect` show the **packaging** version, not necessarily the runtime version: check the startup logs. The cached packages are in the same sensitive named volume as the credentials and persist after an image upgrade. Do not start two containers sharing that volume at once.

**Disable automatic updates / fall back to bundled runtime:**

```bash
RDC_ALLOW_HOST_ADMIN=true RDC_AUTO_UPDATE=false ./update.sh egori4/rdc-host-admin:0.2.0
```

Run this from a separate host session. Disabling immediately selects the image's bundled version at the next start, ignoring cached runtime versions; it does not delete them. Re-enabling can reuse an existing cached runtime. A CLI `--help` smoke check is not an end-to-end Remote session guarantee; if a new runtime has issues, use this opt-out and investigate. Avoid enabling unattended upstream code updates on hosts where root-equivalent changes require approval.

### B. Upgrade the Docker image itself (OS/tools/packaging)

Review the new image release and use an exact version or digest:

```bash
docker pull egori4/rdc-host-admin:<version>
RDC_ALLOW_HOST_ADMIN=true ./update.sh egori4/rdc-host-admin:<version>
```

`update.sh` validates the new image's role label before stopping anything. It preserves device name, state volume, CPU/RAM/PID settings, restart policy, RDC auto-update choice and running/stopped state. The old container is renamed to a timestamped `rdc-host-admin-rollback-...` name and kept stopped. If replacement creation or the immediate process-start check fails, it restores the old container automatically.

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
docker run --rm --network none   --mount type=volume,src=rdc-host-admin-state,dst=/state,readonly   --entrypoint tar egori4/rdc-host-admin:0.2.0 -C /state -czf - . > /secure/path/rdc-state.tar.gz
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
docker pull egori4/rdc-host-admin:0.2.0
docker save egori4/rdc-host-admin:0.2.0 | gzip > rdc-host-admin-0.2.0.tar.gz
```

Transfer the image archive and the tagged source/installer bundle using an approved channel. On the target:

```bash
gunzip -c rdc-host-admin-0.2.0.tar.gz | docker load
./install.sh
```

The installer uses a matching local image without pulling it again. Runtime remote pairing/connectivity still requires outbound Internet access. This supports separate labs without direct connectivity between them.

## 11. Resource settings and limitations

Install overrides: `RDC_CPUS`, `RDC_MEMORY`, `RDC_PIDS_LIMIT`, `RDC_RESTART_POLICY`, `RDC_HOST_ADMIN_IMAGE`, `CONTAINER_NAME`, `STATE_VOLUME`, `RDC_DEVICE_NAME`, `RDC_AUTO_UPDATE`, `START_NOW`.

The normal image is larger than the restricted client because it includes a real browser and administration tools. Memory-intensive browser or data jobs can need more than the default 1 GiB. Host-administration operations launched through Docker or host services may run outside these resource limits. RDC's own persistent workspace/log files are not governed by the Docker stdout log-rotation limit.

No SELinux host-root relabeling is performed: never add `:Z` or `:z` to the host `/` mount. Hosts with additional mandatory-access policies require their own review. Do not disable unrelated platform security globally to make an installation work.
