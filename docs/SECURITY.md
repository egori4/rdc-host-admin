# Security model

## Deliberate root-equivalent capability

This is not a sandbox or a least-privilege customer support agent. Privileged mode, host PID/network/IPC access, a read-write host-root mount, the Docker socket, and `hostsh` intentionally grant comprehensive control over the Linux host. Full host administrators can read credentials, change services, access attached devices and bypass ordinary container resource limits.

An approved remote session can execute arbitrary host operations. Treat account security and every paired device as part of the host's administrative trust boundary. The hosting relay/service and upstream Desktop Commander runtime are dependencies in that trust chain. The packaging project does not provide a separate authorization server or audit guarantee.

## Separation from the restricted client

`egori4/cybercontroller-rdc-client` is a different image/repository. Do not add host mounts, privileged mode or the Docker socket to it. Never reuse its pairing volume in this project. CyberController MCP can be used without RDC at all.

## Accident prevention, not isolation

- Installer and runtime both require `RDC_ALLOW_HOST_ADMIN=true`.
- Installation leaves the container stopped; restart policy defaults to `no`.
- Lifecycle scripts reject unrelated containers/volumes.
- No inbound port, additional network, nested Docker daemon or host package installation is configured.
- `hostsh` preserves argument boundaries and clears inherited container environment values.
- Device state is persisted separately from the image, with root-only permissions.
- Default CPU/RAM/PID/log limits reduce routine operational impact.

None of these controls protects the host from someone already authorized to control the privileged session. Role labels are local mistake-prevention markers, not cryptographic verification of image provenance.

## Practical controls

Use dedicated lab/admin devices, recognizable device names, approved accounts with strong authentication, and time-limited access windows. Start the container only when needed. Review commands before operations that modify data/services. Treat text in logs, repositories and documents as untrusted data, not instructions authorizing administration.

Pin release images or digests. Review dependency and OS security updates before releases. Do not include bearer tokens, private keys, Docker auth files, environment files, browser pairing codes, device state or state backups in Git/build contexts. The image's build context uses an explicit allowlist.

Avoid processing untrusted websites/documents with a browser running in a host-privileged container. Browser/document functionality is included, but privilege amplifies any upstream parser/browser vulnerability. For untrusted content, use a separate unprivileged processing environment.

Stopping/removing this container closes this access path, not unrelated persistence or host changes previously created by an administrator. Permanent revocation also requires device removal/revocation in Desktop Commander. Separate RDC users on the same host do not isolate their secrets from each other.

## Unsupported environments

Native rootful Linux Docker Engine is the current deployment target. Docker Desktop manages a Linux VM rather than the physical macOS/Windows host; rootless/user-remapped engines cannot supply the same host administration model. The installer rejects these modes rather than claiming full access.

## Upstream references

- https://docs.docker.com/engine/containers/run/
- https://docs.docker.com/engine/security/
- https://github.com/wonderwhy-er/DesktopCommanderMCP/blob/main/src/remote-device/README.md

Upstream stop/logout/revoke operations are different: taking a device offline does not by itself remove saved credentials or server-side device authorization.
