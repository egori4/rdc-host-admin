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
1. Obtain approval for two test accounts and a lab Docker host. Create *new* independent test state (no copies of an existing pairing volume). Pin the same upstream runtime version used for both processes.
2. Run two processes with distinct actual `HOME` values, and verify that the corresponding `os.homedir()`, device JSON, MQTT certificate files, MCP config and log paths are distinct. If an upstream runtime version behaves differently, record it.
3. Pair process A to account A, process B to account B using separate verification flows. Check visible device/account associations without exposing secrets.
4. From both independently authenticated AI clients, call one safe, read-only tool (`get_file_info`, `list_directory` or `start_process` with a read-only command) on a uniquely identified lab host; verify requests are routed to the intended shared host and are isolated by cloud device identity.
5. Restart both processes, verify reconnect without browser prompts. Revoke **only B** via the supported server-side flow, verify A still works and B fails; test fresh pairing of B.
6. Exercise simultaneous, read-only calls and verify each client gets the correct response. Record ambiguous logs, duplicate names, backend rejection or cross-account interference.

**DoD:**
- [ ] Two accounts have distinct device IDs, credentials and registration ownership.
- [ ] Both accounts independently reach the same authorized host.
- [ ] Credentials do not collide; both reconnect after restart.
- [ ] Revoking B has no observable effect on A.
- [ ] Concurrent read-only calls behave correctly.
- [ ] No existing credentials/devices were touched; evidence and upstream runtime version recorded.
- [ ] A documented PASS/FAIL and owner GO/NO-GO recorded before Phase 1.

**If FAIL:** stop implementation. Document exact failure and point to upstream [#884](https://github.com/wonderwhy-er/DesktopCommanderMCP/issues/884). Continue using separate containers or await officially supported team/device sharing.

## Phase 1 — opt-in multi-process launch

**Goal:** one container can launch existing primary plus a small number of independent extra operators; unchanged single-user default.

Suggested touch points (not a mandate to redesign):
- `scripts/rdc-runtime.sh`: select/download the runtime once, then only for a *nonempty valid roster* dispatch the same selected binary to a new small runner. Keep direct `exec "$active_bin" "$@"` for absent/empty roster.
- `scripts/rdc-operators-supervisor.sh` (or similarly named): validate roster and resolve child homes, start primary with existing environment and additional processes with individual `HOME` and process-group-aware stop handling. Reap children. Do not pass roster entries into a shell `eval`.
- `docker-entrypoint.sh` / `Dockerfile` as needed: include runner and safe directory initialization without breaking original symlinks or default config.
- `tests/test_runtime.py` plus new supervisor-specific tests.

Design details to implement:
- Persistent text roster `/var/lib/rdc-host-admin/operators.list`; missing/empty is default (legacy). Strict identifier validation, duplicates rejected, max 4 extras, `primary` reserved; validate every line before launching extras.
- All extra operator home directories beneath the known state volume, mode 0700, individually initialized with account-specific config; do not use `DC_ENV` as a multi-account selector.
- For invalid/missing-access roster, log a sanitized error and start **primary only**. A malformed roster must never substitute the wrong identity or prevent the existing primary from starting.
- Primary identity/arguments/config unchanged. **Primary unexpected exit:** terminate and reap extras; exit nonzero. **Extra unexpected exit:** bounded retry (at most three quick failures over five minutes) then leave offline; no container-wide crash or busy loop. Normal stop cleanly ends all children.
- Keep timeout/stop semantics reasonable given current `--stop-timeout 20` and `tini -s -g`; ensure no left-behind processes. A deliberate container stop should not trigger extra restarts.
- Allow distinct lab accounts while **not** implementing per-user OS isolation, hot reload or any hosted authentication service.

**Unit / mock tests (unprivileged):**
- [ ] No roster launches exactly the legacy direct single RDC command; same environment, HOME and saved state paths.
- [ ] Empty roster also takes single-agent path.
- [ ] Valid 1/2/4 extras launch distinct homes with the same selected executable; primary uses legacy home.
- [ ] Reject duplicate, reserved, invalid/traversal, overly long names, >4 entries, symlink roster, insecure file and invalid permissions; fall back to primary only.
- [ ] Stub executables prove no copied tokens or cross-home writes.
- [ ] Stub primary exit terminates all extras; stub extra crash retries only that extra and stops retrying at threshold.
- [ ] TERM/INT/STOP reaps all children without orphan processes, never reboots host or stops unrelated Docker objects.
- [ ] Missing npm/network, cached runtime and `RDC_AUTO_UPDATE=false` all select one shared version per start; no concurrent npm installs.
- [ ] Old `python3 -m unittest discover -s tests -v` and `bash -n` checks still pass.

**Phase 1 DoD:** all listed tests pass; isolated container starts with no roster unchanged; multi-agent stub integration succeeds; no real account/production pairing in automated tests; no functional changes to old install behavior without opt-in.

## Phase 2 — manage operators safely; upgrade/rollback compatibility

**Goal:** safe manual lifecycle without direct edits to credentials or a permanent management service.

Proposed smallest interface: one shell helper `scripts/rdc-operator.sh`:
- `list`: list only sanitized operator IDs and enabled/disabled state based on roster, without claiming device is online/verified; never dump secrets.
- `add <id>`: validate ID, maximum and duplicates; create a missing extra home with strict mode and atomically add ID to roster; no automatic pairing, no process restart.
- `disable <id>`: atomically remove ID from enabled roster. **Does not revoke credentials** and does not delete a home. Print the mandatory follow-up: revoke the corresponding device in its account, restart the container via independent host access, and verify process absence.
- Use atomic temporary-file + rename; one writer at a time (e.g. `flock` if already present), fixed state path, avoid symlink redirection and TOCTOU hazards. Keep interface intentionally limited: no add/remove user API, no secrets output, no hot reload, no delete/purge subcommand in v1.

Avoid new install-time prompts or additional Docker objects. `install.sh` remains single-user by default and creates the same named container/volume. State under `operators/` survives image replacement naturally because `update.sh` already retains the volume; document the extra roster-specific assertions and only modify the updater if tests show an actual gap.

**Tests:**
- [ ] `add`/list/disable idempotence/invalid input/size limits and atomicity under concurrent requests.
- [ ] Unprivileged tests ensure no path escapes state volume, symlink writes or inadvertent exposure of pairing files.
- [ ] Existing `install.sh`, `update.sh`, `uninstall.sh` regression tests stay green.
- [ ] Mock upgrade preserves roster and homes, running/stopped state, image role, `RDC_AUTO_UPDATE`, and rollback identity; no active duplicate of the same volume.
- [ ] Repeated restart does not wipe extra configs or silently re-pair the primary.
- [ ] `disable` is visibly different from backend revoke and takes effect only after restart.

Update `README.md`, `docs/DEPLOYMENT.md`, `docs/SECURITY.md`, `docs/VALIDATION.md` and `CHANGELOG.md` to reflect **actual implemented behavior**, especially security boundaries, onboarding/offboarding, updates, diagnostics and recovery. Update `VERSION` / image release metadata only at a separately approved release step, not simply because a feature branch exists.

**Phase 2 DoD:** helper operations and rollback tests pass; documentation is accurate; legacy commands retain compatibility; no new network ports, services, containers or unattended reboots.

## Phase 3 — controlled lab end-to-end and release gate

On a disposable native Linux Docker host (not production):
1. Prove pristine single-user install (with no roster) still pairs, runs, persists state and can be stopped using existing commands.
2. Upgrade a *test* paired single-user volume to the candidate image; verify primary reconnects unchanged. Snapshot test volume before test; demonstrate restore/rollback if candidate fails.
3. Add operator B from a separate authenticated account. Verify simultaneous safe calls, identities and shared host target.
4. Restart container and image-upgrade in lab; both accounts reconnect. Inject an extra-agent crash, extra auth failure and network loss; verify primary survives and no tight restart loop.
5. Terminate primary; verify extras are stopped. `docker stop` must leave no extra child running. Review logs for sanitized identities and secrets.
6. Disable/revoke B; ensure B no longer reaches host, A remains connected, and retained credentials are documented as still sensitive unless explicitly purged.
7. Test an invalid roster; it must fail closed for extras while the primary remains functional. Verify the current resource defaults and what to adjust if lab memory/PIDs require it.
8. Run all existing unit/smoke/lifecycle tests and the new targeted checks on unique disposable resources; never change an unrelated service.

**Phase 3 DoD / release checklist:**
- [ ] All existing unit tests and new unit tests pass.
- [ ] All required lab E2E flows above pass, including restart, upgrade and rollback.
- [ ] No credential or pairing code appears in logs/artifacts; no unrelated host impact.
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
- Keep all writes within the test branch, lab state and explicitly authorized targets; no production changes until the separate rollout decision.

## References

- [Architecture proposal](MULTI_USER_ARCHITECTURE.md)
- [Current deployment contract](DEPLOYMENT.md)
- [Security model](SECURITY.md)
- [Upstream Desktop Commander Remote README](https://github.com/wonderwhy-er/DesktopCommanderMCP/blob/main/src/remote-device/README.md)
- [Upstream multiple accounts discussion #884](https://github.com/wonderwhy-er/DesktopCommanderMCP/issues/884)
- [Upstream conversation-scoped session discussion #722](https://github.com/wonderwhy-er/DesktopCommanderMCP/issues/722)
