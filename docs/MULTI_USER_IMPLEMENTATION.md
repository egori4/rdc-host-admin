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
| 0 | Verify the upstream service with two accounts | Manual, disposable lab | Must PASS before writing functional multi-user code |
| 1 | Introduce operator homes, roster and bounded supervisor | Functional, opt-in | Unit tests + lab lifecycle |
| 2 | Add safe operator management and upgrade preservation | Functional, documentation | Regression and rollback tests |
| 3 | End-to-end concurrency, resilience and security validation | Test/bug fixes | Release candidate review |
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

**Goal:** one container can launch existing primary plus a small number of independent extra operators; unchanged single-user default.

Suggested touch points (not a mandate to redesign):
- `scripts/rdc-runtime.sh`: select/download the runtime once and use one shared roster-aware dispatch covering **all three current `exec` paths** (auto-update disabled, cache unavailable, normal start). For missing/empty roster, preserve the legacy direct `exec "$active_bin" "$@"`; for one validated extra, launch the small runner with that same selected executable.
- `scripts/rdc-operators-supervisor.sh` (or similarly named): validate roster and resolve child homes, start the primary with existing environment and the extra with its own `HOME`, and correctly stop/reap child processes. Do not pass roster entries into shell `eval`. Tests determine the simplest reliable signal/process-group implementation.
- `docker-entrypoint.sh` / `Dockerfile` as needed: include runner and **initialize the extra's unrestricted config before its agent can launch**. Keep original primary symlinks, credentials and default config untouched.
- `tests/test_runtime.py` plus new supervisor-specific tests.

Design details to implement:
- Persistent text roster `/var/lib/rdc-host-admin/operators.list`; missing/empty is default (legacy). Strict identifier validation, duplicates rejected, **v1 maximum one extra**, `primary` reserved; validate every line before launching extras. Raise the cap only after Phase 3 measurements and separate review.
- All extra operator home directories beneath the known state volume, mode 0700; **create and check each extra's unrestricted `~/.claude-server-commander/config.json` before starting that agent** so upstream cannot silently fall back to restricting file tools to `HOME`. Do not use `DC_ENV` as a multi-account selector. Any `~/.ssh`, `~/.docker`, Git config, shell history or other files that the operator creates in that home are sensitive persistent state.
- For invalid/missing-access roster, log a sanitized error and start **primary only**. A malformed roster must never substitute the wrong identity or prevent the existing primary from starting.
- Primary identity/arguments/config unchanged. Follow the **exit-code contract** from the architecture:

  | Event | Expected result |
  | --- | --- |
  | Primary exits 0, including remote `shutdown` | Stop/reap extra and exit container 0 |
  | Primary exits nonzero | Stop/reap extra; preserve nonzero failure |
  | Extra exits 0, including remote `shutdown` or during shutdown | Leave extra offline, **no retry** |
  | Extra exits nonzero outside container shutdown | Bounded retry of that extra only (at most three quick failures in five minutes); primary stays up |
  | Container stop / `tini -g` group-wide SIGTERM | Graceful shutdown, no crash count/retry, no orphaned child/background processes |

- Define `quick failure` before implementing retry (e.g. exit within 30 seconds after launch); keep timeout/stop within current `--stop-timeout 20` and `tini -s -g`. The supervisor's own messages can identify operators, but **do not pipe or transform the primary's output** or add a log-routing service.
- Allow distinct lab accounts while **not** implementing per-user OS isolation, hot reload or any hosted authentication service.

**Unit / mock tests (unprivileged):**
- [ ] No roster launches exactly the legacy direct single RDC command; same environment, HOME and saved state paths.
- [ ] Empty roster also takes single-agent path.
- [ ] Exactly one enabled extra launches with a distinct `HOME` and the same selected executable; primary uses legacy home. Missing/empty roster is unchanged; **disabled entries never start on the next container startup**.
- [ ] Reject duplicate, reserved, invalid/traversal, overly long names, **more than one extra**, symlink roster, insecure file and invalid permissions; fall back to primary only.
- [ ] Stub executables prove no copied tokens or cross-home writes. **Before extra process launch**, verify its unrestricted config file exists and points to the extra's actual `HOME`.
- [ ] Stub primary exit **0** and **nonzero** both terminate/reap extras with correct container status; stub extra exit **0** never retries (including during shutdown); extra nonzero crash retries only that extra and stops at threshold.
- [ ] TERM/INT/STOP reaps all children, never reboots host or stops unrelated Docker objects. Specifically verify **`tini -g` group-wide SIGTERM is not counted as a crash and triggers no retries**.
- [ ] **Repeated extra crashes/retries do not leave background processes or orphaned descendants**, even when an extra started children before failing.
- [ ] Missing npm/network, cached runtime and `RDC_AUTO_UPDATE=false` all select one shared version per start; no concurrent npm installs.
- [ ] Old `python3 -m unittest discover -s tests -v` and `bash -n` checks still pass.

**Phase 1 DoD:** all listed tests pass; isolated container starts with no roster unchanged; multi-agent stub integration succeeds; no real account/production pairing in automated tests; no functional changes to old install behavior without opt-in.

## Phase 2 — manage operators safely; upgrade/rollback compatibility

**Goal:** safe manual lifecycle without direct edits to credentials or a permanent management service.

Proposed smallest interface: one shell helper `scripts/rdc-operator.sh`, **copied into the Docker image** with a corresponding `Dockerfile COPY` line. Run it **inside the existing running container** via `docker exec rdc-host-admin /usr/local/bin/rdc-operator list|add <id>|disable <id>` (illustrative alternatives; invoke each command separately). Do not create another container to edit the volume. Because the helper requires a running container, if emergency access is cut off by stopping first, **keep that container stopped** until a trusted host administrator can safely update the roster out of band.
- `list`: list only sanitized operator IDs and enabled/disabled state based on roster, without claiming device is online/verified; never dump secrets.
- `add <id>`: validate ID, maximum and duplicates; create a missing extra home with strict mode and atomically add ID to roster; **normal device-code pairing happens when the operator starts after an explicit restart**, no dedicated `pair` command.
- `disable <id>`: atomically remove ID from enabled roster; never start this operator on later container launches. **Does not stop an already running agent**, revoke credentials or delete its home. Print the needed stop/restart and backend revocation steps.
- Use atomic temporary-file + rename; one writer at a time (e.g. `flock` if already present), fixed state path, avoid symlink redirection and TOCTOU hazards. Keep interface intentionally limited: **no pairing subcommand**, no add/remove user API, no secrets output, no hot reload, no delete/purge subcommand in v1. Operator home state, including device/transport credentials, `~/.ssh`, `~/.docker` and shell history, is retained after disable and requires separately authorized secure purge.

Avoid new install-time prompts or additional Docker objects. `install.sh` remains single-user by default and creates the same named container/volume. State under `operators/` survives image replacement naturally because `update.sh` already retains the volume; document the extra roster-specific assertions and only modify the updater if tests show an actual gap.

**Tests:**
- [ ] `docker exec` invokes the copied helper inside the existing running container; `add`/list/disable idempotence, invalid input, **one-extra** size limit and atomicity under concurrent requests all work; no helper container or runtime restart is created.
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
3. Add **one** extra operator B from a separate authenticated account. Verify its unrestricted configuration exists **before** agent launch, then test normal device-code pairing, simultaneous read-only calls, identities and shared host target.
4. Restart container and image-upgrade in lab; both accounts reconnect. Inject an extra-agent crash, extra auth failure and network loss; verify primary survives and no tight restart loop.
5. Test primary exit **0** (remote `shutdown`) and nonzero separately; verify extras stop and correct exit status propagates. Test extra exit **0** leaves it offline without retry, including during shutdown. During `docker stop`, verify **`tini -g` SIGTERM never triggers a retry**; repeated extra crashes must **not leak background child processes**. Review shared Docker logs as sensitive output (initial/retry pairing URLs may appear); do not preserve unredacted logs as evidence.
6. Test **normal offboarding** (disable B while container runs -> stop -> verify B exited -> revoke device -> restart without B) and **emergency offboarding** (revoke B immediately -> promptly disable while container still runs and stop -> verify -> restart only after disabled). If already stopped before disable, **keep the container stopped** until its roster is safely modified by independent host access. Confirm a revoked B may prompt for re-pairing but is never silently reauthorized, and A reconnects.
7. Measure simultaneous A+B CPU, memory/RSS and PIDs under representative lab actions; do **not** assume the single-user limits (1 CPU / 1 GiB / 512 PIDs) fit. Specify tested multi-user limits before release. Keep roster cap at **one** until Phase 3 evidence and review approve expansion. Test invalid roster: primary remains functional, extras do not launch.
8. Run all existing unit/smoke/lifecycle tests and the new targeted checks on unique disposable resources; never change an unrelated service.

**Phase 3 DoD / release checklist:**
- [ ] All existing unit tests and new unit tests pass.
- [ ] All required lab E2E flows above pass, including restart, upgrade and rollback.
- [ ] No credential, token or pairing URL/code appears in **committed/captured test artifacts**; treat live Docker logs as sensitive because upstream device-code pairing can print URLs. No unrelated host impact.
- [ ] `tini -g` stop causes no spurious retry; repeated extra crashes leave no background child processes; extra config exists before launch.
- [ ] Failed B cannot block A; failed A cannot leave an unmanaged remote access process online.
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
- Do not add a `pair <id>` command or log-multiplexing subsystem unless Phase 0 or 3 shows a concrete need. Runtime selection must remain version-aware; test the actual upstream version started, not only the image-bundled fallback.
- Keep all writes within the test branch, lab state and explicitly authorized targets; no production changes until the separate rollout decision.

## References

- [Architecture proposal](MULTI_USER_ARCHITECTURE.md)
- [Current deployment contract](DEPLOYMENT.md)
- [Security model](SECURITY.md)
- [Upstream Desktop Commander Remote README](https://github.com/wonderwhy-er/DesktopCommanderMCP/blob/main/src/remote-device/README.md)
- [Upstream multiple accounts discussion #884](https://github.com/wonderwhy-er/DesktopCommanderMCP/issues/884)
- [Upstream conversation-scoped session discussion #722](https://github.com/wonderwhy-er/DesktopCommanderMCP/issues/722)
