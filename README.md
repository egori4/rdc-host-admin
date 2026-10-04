# RDC Host Admin

A self-contained **Desktop Commander Remote** container for root-equivalent administration of a **native Linux Docker host**. Node.js, the pinned RDC runtime, Python, shell/network utilities, Docker CLI/plugins, and Chromium are included in the image. The host needs Docker Engine and Bash, not Node/npm.

> **This is intentionally privileged, not sandboxed.** Anyone who controls the paired RDC session can read host files and secrets, change the operating system, control Docker, and disrupt services. Install only on a host you are authorized to administer.

## Choose the right project

| Repository | Role | Direct host administration |
| --- | --- | --- |
| [cybercontroller-mcp](https://github.com/egori4/cybercontroller-mcp) | CyberController Evidence MCP server | Only the server's documented evidence access |
| [cybercontroller-rdc-client](https://github.com/egori4/cybercontroller-rdc-client) | Restricted, optional RDC-to-MCP bridge | No host-root mount, Docker socket, or privileged mode |
| **rdc-host-admin** | Generic remote host administration | Root-equivalent, by design |

These are separate repositories and images. There is no restricted/full toggle. This project does not require CyberController, an Evidence MCP token, or an MCP CA certificate. RDC is only one possible consumer of CyberController MCP; n8n and other MCP clients do not need either RDC container.

## Install a published image

```bash
git clone https://github.com/egori4/rdc-host-admin.git
cd rdc-host-admin
./install.sh
```

Read the warning and type `HOST-ADMIN`, then choose a recognizable device name. The installer creates a **stopped** container by default. Start and pair it with your intended Desktop Commander account:

```bash
docker start -ai rdc-host-admin
```

Open the verification URL shown by RDC. Pairing, configuration, and `/workspace` persist in the dedicated `rdc-host-admin-state` volume. Ctrl+C in the attached session can stop the container; use a second terminal with `docker start rdc-host-admin` for detached operation after pairing.

**The complete operator guide is [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).** It covers offline installation, multiple accounts, updates, rollback, access revocation and uninstall.

Default image: `egori4/rdc-host-admin:0.1.0`. Use an exact release or image digest, not `latest`, for controlled deployments.

## Working with the host

File tools can access the host under `/host`. Commands normally run in the container, with its included utilities. Use `hostsh` to run a command in the host's namespaces and filesystem:

```bash
docker exec rdc-host-admin hostsh hostname
docker exec rdc-host-admin hostsh docker ps
docker exec rdc-host-admin hostsh systemctl status docker --no-pager
docker exec rdc-host-admin hostsh sh -lc 'uname -a; df -h /'
```

`hostsh` passes arguments unchanged; it does not join them into an evaluated shell string. Use an explicit `sh -lc '...'` only when shell syntax is intended. It clears inherited container environment values before invoking the host command.

The container has a separate display hostname; `hostsh hostname` reports the real host hostname. The bundled modern Docker CLI may not negotiate with older engines; `hostsh docker ...` uses the host's matching CLI instead.

## Scope and defaults

Native Linux/rootful Docker only. Docker Desktop, rootless engines, daemon user-namespace remapping, remote Docker contexts, Windows, macOS, and Kubernetes are not supported by this installer. Version 0.1.0 is built/tested for `linux/amd64` only.

No Docker network is created and no inbound port is published. Runtime uses host network, PID and IPC namespaces; UTS stays private to permit the independent RDC device name. Host `/` and the Docker socket are mounted read-write. `hostsh` can enter the host UTS and mount namespaces when needed.

Default limits: 1 CPU, 1 GiB RAM, 512 PIDs, 256 MiB `/tmp`, Docker logs 20 MiB x 3, restart policy `no`. These constrain ordinary workloads but are **not a security boundary**: a host administrator can bypass them, for example by asking Docker to launch another container.

The full image includes real Chromium rather than the restricted client's browser placeholder. It is consequently larger. Headless document processing is supported; this is **not** an RDP server or a graphical desktop, and a host display session is not provisioned.

## Development and release

```bash
python3 -m unittest discover -s tests -v
docker build -t egori4/rdc-host-admin:0.1.0 .
# Explicitly privileged integration test on your own disposable/lab Linux host:
RDC_ALLOW_HOST_ADMIN=true ./scripts/smoke-test.sh egori4/rdc-host-admin:0.1.0
```

See [validation results](docs/VALIDATION.md), [security](docs/SECURITY.md), [release process](docs/RELEASING.md), and [changelog](CHANGELOG.md). Image builds use digest-pinned base images and an npm lockfile with Desktop Commander 0.2.52. OS packages are resolved from Debian repositories at build time; this is not a bit-for-bit reproducible OS build.
