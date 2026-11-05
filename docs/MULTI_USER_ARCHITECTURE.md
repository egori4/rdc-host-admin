# Multi-operator RDC Host Admin — architecture proposal

**Status:** DRAFT / FOR REVIEW ONLY · 2026-11-05  
**Scope:** one privileged Linux host, one RDC Host Admin container, multiple independent Desktop Commander accounts.  
**Implementation:** NOT AUTHORIZED by this document. See [implementation plan](MULTI_USER_IMPLEMENTATION.md).

## Decision to approve

Use **one existing container and state volume** with the current paired account as the **primary operator**, plus an **opt-in set of extra Desktop Commander Remote processes, one per named operator**. Each extra process runs with its own persistent `HOME` and independently pairs with its owner's Desktop Commander account. All processes use the same selected Desktop Commander runtime and have the same root-equivalent host access. **Do not enforce an arbitrary numeric user cap**; actual concurrency is constrained by container/host resources and upstream service behavior.

**Hard prerequisite:** prove on a disposable lab host that the Desktop Commander hosted service accepts two independent account/device registrations from one container, routes both correctly, and revokes either without affecting the other. Until this passes, this is a *candidate design*, not a promised upstream capability.

## Current facts and upstream dependency

- `docker-entrypoint.sh` launches `rdc-runtime.sh remote`; the runtime launcher selects one npm version (with its current auto-update/fallback behavior) and execs one RDC process.
- `install.sh` creates one `rdc-host-admin` container and one `rdc-host-admin-state` volume. Existing `device/`, `config/` and `workspace/` paths are persisted. `update.sh` preserves this volume during image replacement/rollback.
- The current deployment guide supports separate account/device identities by using separate containers and volumes; it provides no multi-user gateway.
- Upstream account/device files and local MCP configuration derive from Node's `os.homedir()`; separately set `HOME` values are a plausible state-separation mechanism **to validate against the actual runtime selected on startup**, not a security boundary. Device logs, reports and transport credential paths can change between upstream releases; do not assume a fixed MQTT or Supabase layout.
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
ChatGPT B -> RDC service (account B) -> extra RDC process B -----+--> same privileged
ChatGPT C -> RDC service (account C) -> extra RDC process C -----+    container -> /host,
                      (more operators...)                        hostsh, docker.sock
                  1 container + 1 persistent state volume
                  1 selected runtime per start; one agent per operator
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
      .desktop-commander-device/         # Bob's device session and transport state
      .claude-server-commander/          # Bob's MCP configuration/history
      .ssh/, .docker/, shell history     # possible files created by operator commands
    carol/                               # another independently paired operator home
      .desktop-commander-device/
      .claude-server-commander/
~~~

- **Primary:** preserve current `HOME=/root` and current symlinks under `/root`, without relocating/re-writing existing device credentials.
- **Extra:** explicitly assign `HOME=/var/lib/rdc-host-admin/operators/<id>` to that process and inherited MCP child. **Create and validate the extra's unrestricted host-admin `config.json` before launching the process** (matching primary defaults); otherwise upstream may fall back to restricting file tools to that user's home. Never copy tokens or files from another operator. Verify the effective device, transport, log, report and MCP config paths for the *selected* runtime. Because `~` resolves under this distinct `HOME`, SSH keys, Docker credentials, Git settings and shell history may also be stored there.
- **Roster:** optional root-owned regular file `operators.list`, mode `0600` under mode-`0700` state directory. It contains one operator identifier per line, never an email, credential or command string. Blank/comment lines may be ignored. Allow only `^[a-z][a-z0-9_-]{0,31}$`; reserve `primary`; reject duplicate names, invalid identifiers, symlinks/nonregular files and insecure permissions. **No hardcoded number-of-operators limit**: each valid roster entry starts its own agent on the next container restart, subject to real host/container and upstream service capacity. Reject the entire extra roster on invalid input; never disrupt the primary agent.
- **No roster / empty roster:** current single-agent command and behavior are preserved. A non-empty valid roster enables the multi-agent supervisor on the next explicit container restart. **A disabled operator (absent from the roster) must never launch or be retried on a subsequent startup**; disabling a currently running operator requires stopping/restarting the container, because v1 has no hot reload.
- The readable label `bob` is local metadata, **not verified account ownership**. Verify which cloud account approved each new device when pairing.

## Startup and lifecycle — minimum change

1. The existing `rdc-runtime.sh` selects the RDC executable only once per container startup, including **all three current dispatch paths**: auto-update disabled, runtime cache unavailable and normal update/check. For no/empty roster it preserves the direct legacy `exec ... remote` behavior; otherwise it passes the selected executable to a small multi-agent runner.
2. The runner starts the **primary** RDC process with its unchanged environment and paths, then iterates over all validated roster entries and launches one extra RDC process per operator with its own `HOME`. All use the same selected executable, without simultaneous npm writes or duplicate volume mounts. Do not special-case user names or a fixed process count.
3. The runner owns child PIDs, forwards stop signals, waits/reaps children and stops them on `docker stop`. `tini -s -g` remains in place; tests must prove its group-wide SIGTERM does not cause restarts. Supervisor diagnostics identify operator IDs without adding a log-multiplexing system; **do not pipe or alter the primary agent's stdout/stderr**.
4. **Each** extra's nonzero crash may be retried independently with bounded backoff (at most three quick failures in five minutes **per operator**; define a quick failure in implementation/tests, e.g. an exit within 30 seconds of launch). After exhaustion leave that extra offline until explicit container restart. A failure of one extra must not stop or restart the primary or other healthy extras.

   | Event | Required outcome |
   | --- | --- |
   | Primary exits 0 (including remote `shutdown`) | Stop/reap extras; exit container 0 |
   | Primary exits unexpectedly/nonzero | Stop/reap extras; propagate nonzero failure |
   | Extra exits 0 (including remote `shutdown` or during stop) | Leave that extra offline; do not retry; other agents continue |
   | Extra crashes/nonzero outside shutdown | Bounded retry only that extra; primary and other extras remain online |
   | Container stops / `tini -g` sends SIGTERM | Terminate/reap all; no crash classification, restart or leftover background processes |

5. Operator list changes apply only on an **explicit restart**, through an independent host/SSH session; no automatic container restart policy change. The default remains `--restart=no`. If an operator is disabled in the roster, the next startup must not spawn that operator.
6. Keep Docker image and container update/rollback semantics: one volume, old rollback container stopped. Never run two containers against that volume at once. Rolling back to an image without multi-user support leaves extras offline; document this explicitly.

A small `rdc-operator` helper, **copied into the image with a matching `Dockerfile COPY` line**, runs **inside the existing running container** via `docker exec rdc-host-admin /usr/local/bin/rdc-operator {list|add <id>|disable <id>}` (illustrative interface). It safely and atomically edits the roster and prints that a container restart is required. Admins may run **`add` repeatedly for different names, then restart once**; on restart each enabled operator starts its own RDC session and independently pairs on first use. There is no fixed operator count, separate helper container, pairing command, dynamic reload or automatic restart. **Disable** removes an agent from the *next* process startup; it does **not** stop an already running process, revoke its server-side device, or delete stored credentials.

## Operator experience (after implementation and explicit rollout approval)

1. The host administrator deploys the upgraded image using the existing update procedure. The primary device's saved credentials and session persist; verify its connection still works without re-pairing.
2. While the container runs, the administrator adds names using `docker exec rdc-host-admin /usr/local/bin/rdc-operator add bob`, then optionally `... add carol`. Each command validates and saves a roster entry and per-operator home; **no new process starts until restart**.
3. Using independent host/SSH access, run `docker restart rdc-host-admin` **once** to apply the roster. This briefly disconnects everyone. The primary and already-paired extras reconnect using saved credentials; new extras start the normal device-code authorization flow.
4. Each colleague privately receives the correct pairing URL/code, signs in to **their own** Desktop Commander account, approves that device and connects from their own ChatGPT/AI client. Verify which device/account is being paired; onboarding one at a time avoids confusion from interleaved shared logs.
5. Additional operators follow the **same add + restart** workflow with no product-defined headcount cap. `list` reports roster membership, not remote readiness or pairing status. Removing access requires the **disable + stop/restart + server-side revoke** procedure below. All operators are root-equivalent.

## Security and operational contract

- All paired users have access to host secrets, `/host`, host namespaces and `docker.sock`. Separate `HOME` paths prevent accidental token reuse but offer **no isolation against another privileged operator**; do not represent them as RBAC, tenancy separation or per-human audit.
- The operator approving a device must already be explicitly authorized for full host administration. **Every added account increases the number of credentials that can grant root-equivalent host access.** Keep `docker logs` and pairing codes private; do not copy tokens or pairing URLs into Git, issues or CI output. When several new agents pair after the same restart, their prompts may interleave; verify the right code, account and device ID before each approval, or onboard them one at a time.
- **Normal offboarding:** use the helper to disable B while the container is running, **stop the container via an independent host session**, verify B's process has exited, revoke B's server-side device in the Desktop Commander dashboard, and restart the container with B absent from the roster. Stopping alone does not revoke server-side credentials. This briefly interrupts A because v1 intentionally has no per-agent hot stop.
- **Emergency offboarding:** **revoke B immediately** to cut off existing remote authorization; then, as promptly as possible, use `docker exec` to disable B **while the container is still running**, stop the container, verify the process is gone, and restart only with B disabled. If the container is stopped before the helper can run, **keep it stopped** until the roster can be safely changed by an independently authorized host administrator; do not restart with B enabled. A revoked but still-running/retried agent may print a **new pairing URL** to shared Docker logs; that URL is not automatic authorization, but must be treated as sensitive and never approved.
- Disabled operators' state remains under `operators/<id>` pending separately approved secure purge; include device/transport credentials and any `~/.ssh`, `~/.docker`, Git credentials and shell history. Neither disabling nor stopping purges those files.
- Concurrent users can edit the same files and control the same host processes. Agree operational ownership for destructive actions; no automatic host-command locking is introduced.
- Existing **single-user** defaults (1 CPU / 1 GiB RAM / 512 PIDs) remain unchanged for legacy installs. There is **no automatic capacity scaling or guaranteed maximum concurrency**. Each extra agent adds a remote Node process, a local MCP process, logs and possibly children. Exhausting shared memory/PIDs/CPU can disconnect everyone, so measure **1, 2 and 3 total concurrent operators** in Phase 3, provide tested sizing recommendations and warn administrators before increasing concurrency. Never assume the default 1 GiB container will support a growing roster. The existing `update.sh` preserves installed resource limits; resizing requires an explicit reviewed lifecycle procedure, not automatic resizing.
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

- **Gate A — upstream feasibility:** two different accounts pair from independently homed agents in one *disposable* lab container using the runtime **actually selected on startup**; both make read-only calls, have distinct server-side device identities and can revoke one without breaking the other. Record actual state paths and pairing behavior, including any re-pair prompt after revocation. Failure means **stop**, retain separate-container fallback, and do not build a workaround.
- **Gate B — design approval:** owner accepts root-equivalent sharing, roster/explicit restart model and no guaranteed per-user audit. No implementation before approval.
- **Gate C — implementation acceptance:** all phase DoD/tests in [MULTI_USER_IMPLEMENTATION.md](MULTI_USER_IMPLEMENTATION.md) pass on isolated lab resources, **including three independently authenticated operators** (primary plus two extras), resource measurements and primary legacy behavior; an independent production rollout requires separate approval.

**Review needed:** approve this bounded design and gate sequence, or defer until Desktop Commander offers native team accounts. This document does not authorize deploying or enabling extra users.
