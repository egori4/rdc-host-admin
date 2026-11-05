# Multi-operator RDC Host Admin — architecture proposal

**Status:** DRAFT / FOR REVIEW ONLY · 2026-11-05  
**Scope:** one privileged Linux host, one RDC Host Admin container, multiple independent Desktop Commander accounts.  
**Implementation:** NOT AUTHORIZED by this document. See [implementation plan](MULTI_USER_IMPLEMENTATION.md).

## Decision to approve

Use **one existing container and state volume** with the current paired account as the **primary operator**, plus an **opt-in, bounded set of extra Desktop Commander Remote processes**. Each extra process runs with its own persistent `HOME` and independently pairs with its owner's Desktop Commander account. All processes use the same selected Desktop Commander runtime and have the same root-equivalent host access.

**Hard prerequisite:** prove on a disposable lab host that the Desktop Commander hosted service accepts two independent account/device registrations from one container, routes both correctly, and revokes either without affecting the other. Until this passes, this is a *candidate design*, not a promised upstream capability.

## Current facts and upstream dependency

- `docker-entrypoint.sh` launches `rdc-runtime.sh remote`; the runtime launcher selects one npm version (with its current auto-update/fallback behavior) and execs one RDC process.
- `install.sh` creates one `rdc-host-admin` container and one `rdc-host-admin-state` volume. Existing `device/`, `config/` and `workspace/` paths are persisted. `update.sh` preserves this volume during image replacement/rollback.
- The current deployment guide supports separate account/device identities by using separate containers and volumes; it provides no multi-user gateway.
- Upstream account/device files and local MCP configuration derive from Node's `os.homedir()`; separately set `HOME` values are a plausible state-separation mechanism **to validate**, not a security boundary.
- Upstream [issue #884](https://github.com/wonderwhy-er/DesktopCommanderMCP/issues/884) includes a maintainer comment exploring native team-account device sharing. It is not documented as released support. Upstream [issue #722](https://github.com/wonderwhy-er/DesktopCommanderMCP/issues/722) describes shared process/history state across conversations; no per-conversation isolation can be assumed.

## Goals and non-goals

**Goals**

1. Two or more authorized people use **their own Desktop Commander accounts** to administer the same host via **one Docker container**.
2. Preserve the primary account's device identity, credentials, configuration and functionality without re-pairing.
3. Make extra operators explicitly opt-in, independently pairable and independently disableable; survive restart, image upgrade and rollback as appropriate.
4. Keep the implementation small, supportable and safe to operate on an already privileged host.

**Non-goals (v1)**

- No new authentication provider, reverse proxy, HTTP endpoint, database, dashboard, team invitation system or custom MCP protocol.
- No per-user Linux/Docker isolation, roles, read-only mode or guaranteed per-human audit trail. Every approved agent remains **host-root equivalent**.
- No hot-reload or zero-downtime add/remove, no per-conversation process segregation, no automatic backend revocation and no credential sharing.
- No changes to the restricted `cybercontroller-rdc-client` project.

## Proposed topology

~~~text
ChatGPT A -> RDC service (account A) -> primary RDC process ---+
                                                                |
ChatGPT B -> RDC service (account B) -> extra RDC process B -----+--> same privileged
                                                                |    container -> /host,
ChatGPT C -> RDC service (account C) -> extra RDC process C -----+    hostsh, docker.sock
                                                                     
                  1 container + 1 persistent state volume
                  1 runtime version, selected once per start
~~~

Each remote process retains its own cloud device registration. There is **no local multiplexing of accounts** and no transfer of an authenticated session from A to B.

## Storage, configuration and identity

~~~text
/var/lib/rdc-host-admin/                 # existing named volume
  device/                                # UNCHANGED primary credential directory
  config/                                # UNCHANGED primary MCP config
  workspace/                             # existing shared workspace
  runtime/                               # existing selected/cache runtime
  operators.list                         # NEW, optional; one extra operator id per line
  operators/
    bob/                                 # NEW, HOME for Bob's RDC process
      .desktop-commander-device/         # Bob's pairing/session/certificates
      .claude-server-commander/          # Bob's MCP configuration/history
    carol/                               # same structure, separate identity
~~~

- **Primary:** preserve current `HOME=/root` and current symlinks under `/root`, without relocating/re-writing existing device credentials.
- **Extra:** explicitly assign `HOME=/var/lib/rdc-host-admin/operators/<id>` to that process and inherited MCP child. Create its own unrestricted host-admin config (matching primary defaults), without copying tokens or files from another operator. Verify both upstream config and credential paths really resolve under the intended home.
- **Roster:** optional root-owned regular file `operators.list`, mode `0600` under mode-`0700` state directory. It contains only operator identifiers, never email addresses, credentials or command strings. Blank/comment lines may be ignored. Allow only `^[a-z][a-z0-9_-]{0,31}$`; reserve `primary`; reject duplicate names, links/nonregular files, insecure permissions and more than **four** extra operators. Reject the *whole extra-operator roster* on invalid input; do not disrupt the primary agent.
- **No roster / empty roster:** current single-agent command and behavior are preserved. A non-empty valid roster enables the multi-agent supervisor on the next explicit container restart.
- The readable label `bob` is local metadata, **not verified account ownership**. Verify which cloud account approved each new device when pairing.

## Startup and lifecycle — minimum change

1. The existing `rdc-runtime.sh` runs the current auto-update, cache validation and fallback process **once**, chooses one RDC executable, then dispatches either to the existing `exec ... remote` path (no extras) or to a small multi-agent runner.
2. The runner starts the **primary** RDC process with its unchanged environment and paths, and one additional process per validated roster entry with that operator's own `HOME`. All run the same selected executable, without simultaneous npm writes or duplicate volume mounts.
3. The runner owns child PIDs, labels non-secret diagnostic output by operator, forwards container termination signals, waits/reaps children and stops them on `docker stop`. `tini -s -g` remains in place.
4. **Primary exits unexpectedly:** terminate extra children and fail the container, preserving current primary-failure visibility. **Extra exits unexpectedly:** log it and retry with a short bounded backoff (maximum 3 quick failures per 5 minutes); after exhaustion, leave that extra offline until explicit restart. Never restart the whole container or evict the primary just because Bob's login failed.
5. Operator list changes apply only on an **explicit restart**, through an independent host/SSH session; no automatic container restart policy change. The default remains `--restart=no`.
6. Keep Docker image and container update/rollback semantics: one volume, old rollback container stopped. Never run two containers against that volume at once.

A small `rdc-operator` helper can safely perform `list`, `add <id>` and `disable <id>` by atomically editing the roster, then printing that restart is required. **Disable** only removes an agent from the next process startup; it **does not revoke** the server-side device or delete stored credentials. No dynamic reload or automatic restart is required.

## Security and operational contract

- All paired users have access to host secrets, `/host`, host namespaces and `docker.sock`. Separate `HOME` paths prevent accidental token reuse but offer **no isolation against another privileged operator**; do not represent them as RBAC, tenancy separation or per-human audit.
- The operator approving a device must already be explicitly authorized for full host administration. Keep `docker logs` and pairing codes private; do not copy tokens or pairing URLs into Git, issues or CI output.
- To offboard someone: **revoke their RDC device in their Desktop Commander account/dashboard**; disable that operator in the local roster; restart via an independent host session; verify the disabled agent no longer has a process. Retain or securely purge their local state under a separate explicit decision. Stopping alone does not revoke server-side credentials.
- Concurrent users can edit the same files and control the same host processes. Agree operational ownership for destructive actions; no automatic host-command locking is introduced.
- Default resource limits (1 CPU / 1 GiB) are unchanged. Record per-agent CPU, memory and PID use during lab validation and document when an operator should explicitly raise limits.
- The existing Docker host-admin acknowledgement, host-only target, no published inbound ports and runtime-update security tradeoffs stay intact.

## Alternatives and decision boundaries

| Approach | Decision | Reason |
| --- | --- | --- |
| Share one Desktop Commander account | Reject | No separate user credentials or clean individual revocation |
| **Multiple agents / one container** | **Candidate, conditional on feasibility gate** | Small additive change; one install/state volume |
| Multiple current containers / volumes | Supported fallback | Separate registrations today, at cost of containers |
| Build an auth/multiplexing gateway | Reject for v1 | Adds major security-critical complexity and ongoing maintenance |
| Native upstream team-device sharing | Preferred when officially available | Could remove need for multiple local agents |

## Approval gates

- **Gate A — upstream feasibility:** two different accounts pair from independently homed agents in one *disposable* lab container; both make read-only calls, have distinct server-side device identities and can revoke one without breaking the other. Failure means **stop**, retain separate-container fallback, and do not build a workaround.
- **Gate B — design approval:** owner accepts root-equivalent sharing, roster/explicit restart model and no guaranteed per-user audit. No implementation before approval.
- **Gate C — implementation acceptance:** all phase DoD/tests in [MULTI_USER_IMPLEMENTATION.md](MULTI_USER_IMPLEMENTATION.md) pass on isolated lab resources, primary legacy path remains unchanged, and an independent production rollout is approved separately.

**Review needed:** approve this bounded design and gate sequence, or defer until Desktop Commander offers native team accounts. This document does not authorize deploying or enabling extra users.
