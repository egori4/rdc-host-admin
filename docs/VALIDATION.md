# Initial release validation

Validated on 2026-10-04 using a native Linux amd64 lab host running Docker Engine 29.7.2. These are functional checks, not a production security certification.

| Check | Result |
| --- | --- |
| Mocked installer/lifecycle/argument-handling unit tests | 23 passed |
| Container image build | Passed |
| Runtime refuses missing host-admin acknowledgement | Passed |
| Host root UID, namespace entry and real hostname | Passed |
| Host-shell argument boundaries | Passed, including spaces and shell metacharacters |
| Temporary host file create/read/delete | Passed |
| Disposable host Docker container create/start/stop/delete | Passed |
| Bundled Node, Python, Docker, Compose and Buildx | Passed |
| Real Chromium headless rendering | Passed |
| Actual upstream stdio MCP tool discovery | 26 tools listed |
| Actual MCP start_process invoking hostsh | Returned host UID 0 |
| Workspace/config persistence across restart and recreation | Passed |
| Installer defaults to stopped | Passed |
| Successful image update preserves running state and data | Passed |
| Intentionally failed new image triggers automatic rollback | Passed |
| Uninstall preserves state; explicit purge deletes test state | Passed |

The integration tests used uniquely named temporary containers, volumes and files and cleaned them up. Existing host services and the existing CyberController RDC connection were not replaced or restarted.

## Host reboot / break-glass behavior

Additional lab validation on 2026-10-06 confirmed that the full-admin container remains configured with Docker restart policy `no`. A CyberController host reboot therefore does not intentionally auto-start this root-equivalent remote-access path. Starting `rdc-full` after Docker is available reused the same persisted device identity and reconnected successfully.

For a one-time lab reboot test only, a temporary systemd unit started `rdc-full` after `docker.service`; that test succeeded and the temporary unit was removed afterward. This mechanism is not part of the supported steady-state deployment because the intended security posture is explicit/manual activation of full host-admin access.

Not tested in this release validation: browser pairing of a new remote identity, end-to-end cloud-relayed ChatGPT connectivity for that new identity, real host reboot, ARM64, Docker Desktop, or a customer production deployment. No existing device credential was copied into this new project. Remote pairing remains an operator action.

Reproduce the unprivileged tests with `python3 -m unittest discover -s tests -v`. On an explicitly authorized lab host, run `RDC_ALLOW_HOST_ADMIN=true ./scripts/smoke-test.sh <image>` and `RDC_ALLOW_HOST_ADMIN=true ./scripts/lifecycle-test.sh <image>`.
