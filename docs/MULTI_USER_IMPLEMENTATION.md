# Multi-operator RDC Host Admin — implementation plan for AI coding agent

**Status:** DRAFT / REVIEW ONLY — do not implement, deploy, pair, restart, revoke or modify any running container until explicitly approved.  
**Related design:** [MULTI_USER_ARCHITECTURE.md](MULTI_USER_ARCHITECTURE.md)  
**Target:** additive, opt-in change to `egori4/rdc-host-admin`, not an upstream fork.

## Instructions for implementation agent

1. First read the architecture, `README.md`, `docs/SECURITY.md`, `docs/DEPLOYMENT.md`, `install.sh`, `update.sh`, `docker-entrypoint.sh`, `scripts/rdc-runtime.sh` and all existing tests.
2. Use a dedicated **implementation branch** based on the latest approved base; preserve this documentation branch for review. Work on one phase at a time; commit each completed phase with test results. No production or customer's host access is authorized by this plan.
3. **Do not skip Phase 0.** If upstream cross-account behavior fails, stop and report results. Do not work around account/device isolation by copying tokens, pairing the wrong account, modifying the hosted service, or sharing a single account.
4. Favor Bash + existing `tini` and `rdc-runtime.sh`. No package dependencies, database, reverse proxy, API service, background controller or new Docker container per person.
5. Maintain the exact existing primary device home/credentials and single-agent behavior by default. No migration/rotation of existing primary credentials. Every new feature is opt-in.
6. Never leak credentials, pairing codes, verification URLs or saved device state to commits, test artifacts or reports. Prefer mock/stub agents for automation.
7. After **each phase**, report changed files, test commands/results, unmet DoD, risks and explicit GO/NO-GO for the next phase. Stop at the phase boundary if unresolved concerns remain.

## Estimated scope

Three implementation phases after one **mandatory feasibility phase**; a review-only Phase 4 for optional rollout. The meaningful difficulty is upstream multi-account compatibility and process lifecycle safety, not adding another Docker container.

| Phase | Purpose | Type | Approval boundary |
| --- | --- | --- | --- |
| 0 | Prove upstream supports two separate accounts | Manual, disposable lab | Must PASS before writing functional multi-user code |
| 1 | Introduce dynamic roster, operator homes and bounded supervisor | Functional, opt-in | Unit tests + lab lifecycle |
| 2 | Add safe operator management and upgrade preservation | Functional, documentation | Regression and rollback tests |
| 3 | End-to-end with three accounts, resilience, capacity and security validation | Lab test/bug fixes | Release candidate review |
| 4 | Real-host rollout (not covered by this approval) | Separate change window | Explicit deployment approval |

## Phase 0 — feasibility spike (stop/go)

**Goal:** confirm a shared physical/containerized host can register two RDC device identities to distinct Desktop Commander accounts without overwriting the original. **No change to the production container or the current paired volume.**

Procedure in an explicitly disposable lab:
1. Obtain approval for two test accounts and a lab Docker host. Create *new* independent test state (no copies of an existing pairing volume). **Record the RDC runtime version actually selected at startup** from `rdc-runtime.sh` logs, including whether auto-update was enabled, a cache was used or the bundled fallback was selected. Use the **same selected executable** for both test agents; the bundled package version alone is not sufficient evidence.
2. Run two processes with distinct actual `HOME` values. Verify `os.homedir()` and the **actual** device-session, transport credentials (if present), MCP config, tool history, device logs and diagnostics/report paths used by that selected upstream release. Do **not** assume a fixed `MQTT` certificate layout; document version-specific paths and verify no cross-home writes.
3. Pair process A to account A, process B to account B using separate verification flows. Measure the pairing-code validity window and note where pairing prompts appear; do not put URLs/codes into committed logs or evidence. Check visible device/account associations without exposing secrets.
4. From both independently authenticated AI clients, call one safe, read-only tool (`get_file_info`, `list_directory` or `start_process` with a read-only command) on a uniquely identified lab host; verify requests are routed to the intended shared host and are isolated by cloud device identity.
5. Restart both processes, verify reconnect without browser prompts. On the isolated lab, revoke **only B** via the supported server-side flow and verify A still works and B fails. Observe whether B triggers a *new pairing prompt* while running or after retry; do not approve it. Stop B promptly, then separately test a fresh B pairing. New URLs in Docker logs must be treated as sensitive, **not** as automatic restoration of authorization.
6. Exercise simultaneous, read-only calls and verify each client gets the correct response. Record ambiguous logs, duplicate names, backend rejection or cross-account interference.

**DoD:**
- [ ] Two accounts have distinct device IDs, credentials and registration ownership.
- [ ] Both accounts independently reach the same authorized host.
- [ ] Credentials, configurations and diagnostics do not collide; both reconnect after restart.
- [ ] Revoking B has no observable effect on A; any new pairing prompt is observed safely and B is stopped without reauthorization.
- [ ] Pairing-code lifetime is measured; no dedicated pairing helper is needed unless this phase proves onboarding unreliable.
- [ ] Concurrent read-only calls behave correctly.
- [ ] No existing credentials/devices were touched; evidence includes selected runtime version, auto-update/cache state and verified `HOME`-based paths.
- [ ] A documented PASS/FAIL and owner GO/NO-GO recorded before Phase 1.

**If FAIL:** stop implementation. Document exact failure and point to upstream [#884](https://github.com/wonderwhy-er/DesktopCommanderMCP/issues/884). Continue using separate containers or await officially supported team/device sharing.

## Phase 1 — opt-in multi-process launch

**Goal:** one container launches the existing primary plus **one agent for every configured extra operator**, with no hardcoded numeric roster cap; missing/empty roster retains the unchanged single-user default. Resource capacity is separately measured and documented.

Suggested touch points (not a mandate to redesign):
- `scripts/rdc-runtime.sh`: select/download the runtime once and use one shared roster-aware dispatch covering **all three current `exec` paths** (auto-update disabled, cache unavailable, normal start). For missing/empty roster, preserve the legacy direct `exec "$active_bin" "$@"`; otherwise pass the same selected executable to the supervisor, which launches all validated enabled operators. Avoid repeated npm updates per agent.
- `scripts/rdc-operators-supervisor.sh` (or similarly named): validate the entire roster and resolve individual homes; start the primary with its existing environment and **iterate across all enabled extra operators**, starting one process per validated home. Correctly stop/reap all descendants and apply independent crash-retry budgets per extra. Do not use shell `eval`. Tests determine the simplest reliable signal/process-group implementation; do not assume only one extra exists.
- `docker-entrypoint.sh` / `Dockerfile` as needed: include runner and **initialize the extra's unrestricted config before its agent can launch**. Keep original primary symlinks, credentials and default config untouched.
- `tests/test_runtime.py` plus new supervisor-specific tests.

Design details to implement:
- Persistent text roster `/var/lib/rdc-host-admin/operators.list`; missing/empty is default (legacy). Strict operator ID validation, duplicates rejected, `primary` reserved, and full roster validated before any extra starts. **Do not impose an arbitrary numerical maximum on valid roster entries.** Runtime capacity is constrained by CPU, memory, PIDs and upstream behavior, not a hardcoded product setting.
- All extra operator home directories beneath the known state volume, mode 0700; **create and check each extra's unrestricted `~/.claude-server-commander/config.json` before starting that agent**, so upstream cannot silently restrict file tools to `HOME`. Keep every extra's device/session/transport/log files separate. Do not use `DC_ENV` as a multi-account selector. Any `~/.ssh`, `~/.docker`, Git config, shell history or other files operators create in their home are sensitive persistent state.
- For invalid, unreadable or unsafe roster, log a sanitized error and start **primary only**. A malformed entry must not launch a partial set of extras, substitute the wrong credentials or prevent the existing primary from starting. Disabling one extra must never disable another.
- Primary identity/arguments/config unchanged. Follow the **exit-code contract** from the architecture:

  | Event | Expected result |
  | --- | --- |
  | Primary exits 0, including remote `shutdown` | Stop/reap extra and exit container 0 |
  | Primary exits nonzero | Stop/reap extra; preserve nonzero failure |
  | Extra exits 0, including remote `shutdown` or during shutdown | Leave only that extra offline, **no retry**; others continue |
  | Extra exits nonzero outside container shutdown | Bounded retry of only that extra (at most three quick failures in five minutes per operator); all other agents stay up |
  | Container stop / `tini -g` group-wide SIGTERM | Graceful shutdown, no crash count/retry, no orphaned child/background processes |

- Define `quick failure` before implementing retry (e.g. exit within 30 seconds after launch); keep timeout/stop within current `--stop-timeout 20` and `tini -s -g`. The supervisor's own messages can identify operators, but **do not pipe or transform the primary's output** or add a log-routing service. New agents' pairing prompts can interleave in shared logs: maintain identifiable supervisor startup messages, and verify account/device identity before approving each code.
- Allow distinct lab accounts while **not** implementing per-user OS isolation, hot reload or any hosted authentication service.

**Unit / mock tests (unprivileged):**
- [ ] No roster launches exactly the legacy direct single RDC command; same environment, HOME and saved state paths.
- [ ] Empty roster also takes single-agent path.
- [ ] Test roster-driven launches with **1, 2 and 4 mock extra operators**; every distinct `HOME` and device path is respected, all agents use the same selected executable, and the primary uses the legacy home. No fixed count-specific branching. Missing/empty roster is unchanged, and **disabled entries never start at the next container startup**.
- [ ] Reject duplicate, reserved, invalid/traversal and overly long names, symlink/nonregular roster, insecure permissions and malformed lines; fall back to primary only. **No test should expect rejection solely because there are multiple valid operators.**
- [ ] Stub executables prove no copied tokens or cross-home writes. **Before extra process launch**, verify its unrestricted config file exists and points to the extra's actual `HOME`.
- [ ] Stub primary exit **0** and **nonzero** both terminate/reap **all extras** with correct container status; stub extra exit **0** never retries (including during shutdown); if B crashes, only B retries while the primary and C remain unaffected; each extra stops retrying at its own threshold.
- [ ] TERM/INT/STOP reaps **every** agent and its children without interfering with unrelated Docker objects. Specifically verify **`tini -g` group-wide SIGTERM is not counted as a crash and triggers no retries**, even with multiple extras running.
- [ ] **Repeated extra crashes/retries do not leave background processes or orphaned descendants**, including when B fails repeatedly while C continues normally.
- [ ] Missing npm/network, cached runtime and `RDC_AUTO_UPDATE=false` all select one shared version per start; no concurrent npm installs.
- [ ] Old `python3 -m unittest discover -s tests -v` and `bash -n` checks still pass.

**Phase 1 DoD:** all listed tests pass; isolated container starts without roster unchanged; mocked 1/2/4-extra scenarios prove roster iteration, independent failure handling and no hardcoded count, without asserting unlimited *capacity*; no real-account or production pairing in automation and no functional changes without opt-in.

## Phase 2 — manage operators safely; upgrade/rollback compatibility

**Goal:** safe manual lifecycle without direct edits to credentials or a permanent management service.

Proposed smallest interface: one shell helper `scripts/rdc-operator.sh`, **copied into the Docker image** with a corresponding `Dockerfile COPY` line. Run it **inside the existing running container** via `docker exec rdc-host-admin /usr/local/bin/rdc-operator list|add <id>|disable <id>` (illustrative alternatives; invoke each command separately). Do not create another container to edit the volume. **Repeated `add` commands persist any number of valid operator entries; one explicit container restart applies the entire roster.** No processes should be launched or stopped by `add` or `disable`. Because the helper requires a running container, if emergency access is cut off by stopping first, **keep that container stopped** until a trusted host administrator can safely update the roster out of band.
- `list`: list only sanitized operator IDs and enabled/disabled state based on roster, without claiming device is online/verified; never dump secrets.
- `add <id>`: validate ID and duplicates (not a numeric headcount); create a missing extra home with strict mode and atomically add the entry. **Normal device-code pairing happens when the operator starts after the explicit restart**, no dedicated `pair` command. Two different additions can be followed by one restart; for clearer pairing-code ownership, onboarding one person at a time remains the simplest operating procedure.
- `disable <id>`: atomically remove ID from enabled roster; never start this operator on later container launches. **Does not stop an already running agent**, revoke credentials or delete its home. Print the needed stop/restart and backend revocation steps.
- Use atomic temporary-file + rename; one writer at a time (e.g. `flock` if already present), fixed state path, avoid symlink redirection and TOCTOU hazards. Keep interface intentionally limited: **no pairing subcommand**, no add/remove user API, no secrets output, no hot reload, no delete/purge subcommand in v1. Operator home state, including device/transport credentials, `~/.ssh`, `~/.docker` and shell history, is retained after disable and requires separately authorized secure purge.

Avoid new install-time prompts or additional Docker objects. `install.sh` remains single-user by default and creates the same named container/volume. State under `operators/` survives image replacement naturally because `update.sh` already retains the volume; document the extra roster-specific assertions and only modify the updater if tests show an actual gap.

**Tests:**
- [ ] `docker exec` invokes the copied helper inside the existing running container; add/list/disable handle repeated additions, invalid names, duplicate IDs, atomicity and concurrent requests. **Adding a third and later valid operator is never rejected by an arbitrary roster cap.** Neither the helper nor `add` creates another Docker container or launches a remote agent immediately.
- [ ] Unprivileged tests ensure no path escapes state volume, symlink writes or inadvertent exposure of pairing files.
- [ ] Existing `install.sh`, `update.sh`, `uninstall.sh` regression tests stay green.
- [ ] Mock upgrade preserves roster and homes, running/stopped state, image role, `RDC_AUTO_UPDATE`, and rollback identity; no active duplicate of the same volume.
- [ ] Repeated restart does not wipe extra configs or silently re-pair the primary.
- [ ] `disable` is visibly different from backend revoke and takes effect only after restart; disabled operators never launch again while absent from the roster.

Update `README.md`, `docs/DEPLOYMENT.md`, `docs/SECURITY.md`, `docs/VALIDATION.md` and `CHANGELOG.md` to reflect **actual implemented behavior**, especially security boundaries, onboarding/offboarding, updates, diagnostics and recovery. Update `VERSION` / image release metadata only at a separately approved release step, not simply because a feature branch exists.

**Phase 2 DoD:** helper operations and rollback tests pass; documentation is accurate; legacy commands retain compatibility; no new network ports, services, containers or unattended reboots.

## Phase 3 — controlled lab end-to-end and release gate

On a disposable native Linux Docker host (not production):
1. Prove pristine single-user install (with no roster) still pairs, runs, persists state and can be stopped using existing commands.
2. Upgrade a *test* paired single-user volume to the candidate image; verify primary reconnects unchanged. Snapshot test volume before test; demonstrate restore/rollback if candidate fails.
3. Add extra operator B from a separate authenticated account, verify its unrestricted config exists **before** launch, pair normally, and test safe read-only calls. Then **add C as another independently authenticated operator using the same helper and restart process**; B and primary must reconnect without re-pairing. Test A+B+C simultaneous safe calls and unique credentials/device identities. If several new operators are paired after a single restart, check that interleaved log prompts do not cause incorrect account/device approvals.
4. Restart container and image-upgrade in lab with **A+B+C** configured; all reconnect from saved credentials. Inject B crash, C crash, extra auth failure and network loss; verify primary and unaffected extras survive, and no tight restart loop. Repeated disable/add operations must preserve the other operators' homes and credentials.
5. Test primary exit **0** (remote `shutdown`) and nonzero separately; both must stop **all** extras and propagate correct status. Test B exit **0** leaves it offline without retry while C remains online. During `docker stop`, **`tini -g` SIGTERM never triggers a retry**; repeated B/C crashes must **not leak background child processes**. Review shared Docker logs as sensitive output (initial/retry pairing URLs may appear); do not preserve unredacted logs as evidence.
6. Test **normal offboarding** (disable B while container runs -> stop -> verify B exited -> revoke its device -> restart without B) and **emergency offboarding** (revoke B immediately -> promptly disable while still running, stop, verify -> restart without B). If already stopped before disable, keep the container stopped until its roster is safely modified by independent host access. Verify A and C reconnect normally after restart and that revoked B is never silently reauthorized. Document any re-pairing prompt as sensitive.
7. Measure CPU, RSS/memory, PIDs and log usage with **one, two and three total concurrently connected operators** under representative lab actions; do **not** assume single-user limits (1 CPU / 1 GiB / 512 PIDs) fit. Document tested sizing/headroom and known service limits, and note that `update.sh` currently preserves resource settings (no automatic resize). **No arbitrary code-level roster cap and no claim of unlimited supported concurrency.** Test invalid roster: primary functions, extras do not launch.
8. Run all existing unit/smoke/lifecycle tests and the new targeted checks on unique disposable resources; never change an unrelated service.

**Phase 3 DoD / release checklist:**
- [ ] All existing unit tests and new unit tests pass.
- [ ] All required lab E2E flows pass with **three independently authenticated operators**, including restart, upgrade, rollback, concurrent commands, disable/revoke of one without losing others and preservation of the existing primary pairing.
- [ ] No credential, token or pairing URL/code appears in **committed/captured test artifacts**; treat live Docker logs as sensitive because upstream device-code pairing can print URLs. No unrelated host impact.
- [ ] `tini -g` stop causes no spurious retry; repeated extra crashes leave no background child processes; extra config exists before launch.
- [ ] A failed extra does not take down the primary or other extras; failed primary cannot leave unmanaged remote access processes online. Document measured resource requirements and monitoring/diagnostics for operators planning larger rosters.
- [ ] Documentation and release notes match tested behavior; root-equivalent risks are prominent.
- [ ] Version/tag choice, image provenance, and whether to opt out of RDC auto-update reviewed.
- [ ] Reviewer explicitly approves merge/release after seeing evidence. **No automatic merge or publication.**

## Phase 4 — separate change-control / not part of this plan's authorization

Prepare a production/customer change plan only after explicit request: backup sensitive state while stopped, preflight independent SSH, pairing access for new operators, rollout window, smoke check, abort and rollback instructions, credential revocation validation and monitoring. Do **not** activate on `m920q`, lab210, customer hosts or any existing RDC device as part of writing/planning this document.

## AI-agent test & reporting format

At end of each implementation phase, return:

~~~text
Phase X: PASS / FAIL / BLOCKED
Commit(s): <sha>
Files changed: <paths>
Checks: <command> -> PASS/FAIL and counts
Lab evidence (if any): <read-only non-secret summary>
Unmet DoD: <items>
Risk/decision: <short summary>
Next phase: GO / NO-GO (requires human approval at stated gates)
~~~

### Guardrails / things not to overbuild

- Do not introduce a generic user registry, team admin console, Unix-account management service, RBAC claims or OAuth token broker.
- Do not run a new Docker container for each operator or copy primary credentials.
- Do not silently switch from the primary account to a different one.
- Do not use `DC_ENV` as a profile selector: upstream code may not honor it consistently.
- Do not claim per-user audit isolation or conversation isolation merely because process homes differ.
- Do not add a `pair <id>` command, hardcoded operator cap, dynamic on-add launch, auto-scaling, or log-multiplexing subsystem unless Phase 0/3 proves a concrete requirement. Runtime selection remains version-aware; test the actual upstream version started, not only the image-bundled fallback.
- Keep all writes within the test branch, lab state and explicitly authorized targets; no production changes until the separate rollout decision.

## References

- [Architecture proposal](MULTI_USER_ARCHITECTURE.md)
- [Current deployment contract](DEPLOYMENT.md)
- [Security model](SECURITY.md)
- [Upstream Desktop Commander Remote README](https://github.com/wonderwhy-er/DesktopCommanderMCP/blob/main/src/remote-device/README.md)
- [Upstream multiple accounts discussion #884](https://github.com/wonderwhy-er/DesktopCommanderMCP/issues/884)
- [Upstream conversation-scoped session discussion #722](https://github.com/wonderwhy-er/DesktopCommanderMCP/issues/722)
