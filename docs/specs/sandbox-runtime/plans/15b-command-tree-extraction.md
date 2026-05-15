# Phase 15b — Command tree extraction + structure tests + plan re-anchor (prex task brief)

> Status: Pending
> Companion docs (Codex must read these in stage 1):
> - [docs/specs/sandbox-runtime/IMPLEMENTATION-PLAN.md](../IMPLEMENTATION-PLAN.md) (master overview)
> - [`bashly commands_dir convention`](https://bashly.dev/configuration/command/)
> - The lib/dctl/CLAUDE.md created in round 15a — read it to confirm the naming conventions.
> Depends on: [`15a-helper-tree-and-autoload.md`](15a-helper-tree-and-autoload.md) — must be `Done`. `lib/dctl/_lib/` tree exists, `bin/dctl` uses `__dctl_dispatch`, and the round-15a compatibility shim is in place (flat files `__dctl_require`-ing `_lib/`).
> Output of this round: `lib/dctl/commands/<group>/<verb>.sh` layout exists for all 7 groups. Flat `lib/dctl/{auth,common,config,deploy,image,init,test,ws}.sh` files are deleted (`doctor.sh` becomes `commands/doctor/`). `tests/structure_test.bats` enforces the invariants. Pre-reorg line-number anchors in the remaining briefs are updated to post-reorg paths.

## Task

Phase 1.5 part B. Extract every command-verb implementation from the flat `lib/dctl/{ws,image,init,deploy,config,test,doctor}.sh` modules into the `lib/dctl/commands/<group>/<verb>.sh` layout (one verb per file, one `cmd_<group>_<verb>` function per file). Each group gets a `_dispatch.sh` carrying `usage_<group>` + `main_<group>` (the case statement). Delete the flat modules once their verbs are extracted. Remove the round-15a compatibility shim from `__dctl_dispatch`. Add `tests/structure_test.bats` enforcing the layout invariants. Re-anchor every pre-reorg `file:line` reference in the remaining briefs (`20-*.md`, `40-*.md`, `60-*.md`, `70-*.md`) to its new post-reorg path — this prevents stale anchors from misleading rounds 20–70.

This is a **pure rename + extract pass** with no behavior change. Existing bats tests must still pass against the new command paths.

`deploy.sh` (594 LOC) is the heaviest single module — budget stage 3 accordingly. If stage 3 hits the 10-minute timeout, abort and re-run as `15b-i` + `15b-ii` per the contingency split in `plans/README.md`.

## Preconditions (must already be true on `develop`)

- Round `15a` is `Done`. `lib/dctl/_lib/` exists with one function per file. `bin/dctl` calls `__dctl_dispatch`. The flat `lib/dctl/{auth,common,config,deploy,image,init,test,ws,doctor}.sh` files still exist but contain only verb implementations (helpers moved to `_lib/`).
- `make check` is green.

## Scope (in this round)

### New: `lib/dctl/commands/<group>/` — 7 groups

Each group's `_dispatch.sh` defines `usage_<group>` + `main_<group>` (the case statement that dispatches verbs). Each verb file defines exactly one `cmd_<group>_<verb>` function.

| Group | Source (flat) LOC | Verb files (+ `_dispatch.sh`) |
|---|---|---|
| `commands/ws/` | `ws.sh` (308) | `up.sh`, `reup.sh`, `exec.sh`, `shell.sh`, `run.sh`, `status.sh`, `down.sh` + `_dispatch.sh` |
| `commands/image/` | `image.sh` (301) | `build.sh`, `list.sh` + `_helpers.sh` (`discover_image_targets`, `resolve_containerfile`, `get_image_tag`) + `_dispatch.sh` |
| `commands/init/` | `init.sh` (346) | `do.sh`, `select_interactive.sh`, `generate_cache.sh` + `_dispatch.sh` |
| `commands/deploy/` | `deploy.sh` (594 — **biggest**) | `all.sh`, `list.sh`, `plan.sh`, `apply.sh`, `reset.sh`, `_discover.sh` + `_dispatch.sh` |
| `commands/config/` | `config.sh` (334) | `register.sh`, `unregister.sh`, `list.sh`, `show.sh` + `_dispatch.sh` (validation/registry-IO helpers already moved to `_lib/registry/` in round 15a) |
| `commands/test/` | `test.sh` (290) | `run.sh`, `_summary.sh` + `_dispatch.sh` (the Phase-2 deprecation banner from round 00 stays at the top of `run.sh`) |
| `commands/doctor/` | `doctor.sh` (Phase 0) | `crun_libkrun.sh`, `kvm.sh`, `libkrun.sh`, `subid.sh`, `cgroups.sh`, `podman_info.sh`, `network_backend.sh`, `userns.sh`, `nested_virt.sh` + `_dispatch.sh` — one probe per file matching round 00's probe list |

The Phase 5 `commands/net/` group is created **in round 40**, not here. Mention it in `commands/CLAUDE.md` orientation but do not stub.

### Delete: flat `lib/dctl/*.sh`

After every verb is extracted and tests still pass:

- `lib/dctl/auth.sh` — already gone in round 15a (was 70 LOC of helpers).
- `lib/dctl/common.sh` — verify nothing still imports from it; should be empty after round 15a moved everything to `_lib/`. Delete.
- `lib/dctl/ws.sh`, `image.sh`, `init.sh`, `deploy.sh`, `config.sh`, `test.sh`, `doctor.sh` — delete after their `commands/<group>/` extraction is in place and the structure tests pass.

**Preserved verbatim:** `lib/dctl/runtime/{common,krun}.sh`, `lib/dctl/lifecycle.sh`. Do not touch.

### Remove: round-15a compatibility shim

Round 15a's `__dctl_dispatch` falls back to `source "${DCTL_LIB_DIR}/<group>.sh"; main_<group>` if `commands/<group>/_dispatch.sh` doesn't exist. Delete that fallback once every group has migrated. After this round, `__dctl_dispatch` routes **only** to `commands/<group>/_dispatch.sh`.

### New: `tests/structure_test.bats`

Enforce the layout invariants:

- Every file in `lib/dctl/commands/<group>/` (except `_dispatch.sh` and `_*.sh`) defines exactly one `cmd_<group>_<filename-without-.sh>` function.
- Every file in `lib/dctl/_lib/` defines at most one function.
- No file in `lib/dctl/` exceeds 500 lines (`wc -l` gate).
- `bin/dctl` sources only `_lib/source.sh`, `_lib/log.sh`, `_lib/paths.sh` at startup (no other `source` lines in `bin/dctl`).

### Plan re-anchor pass

Rounds 20, 40, 60, 70 currently reference pre-reorg paths (`ws.sh:58`, `image.sh:255`, `deploy.sh:67`, etc.). Edit each brief to replace those with post-reorg anchors. Representative mapping (full mapping inferred from this round's extractions):

| Pre-reorg anchor | Post-reorg path |
|---|---|
| `lib/dctl/ws.sh:58,64,247` (ps filters) | `lib/dctl/commands/ws/{up,reup,…}.sh` |
| `lib/dctl/ws.sh:84-104 collect_git_worktree_mounts` | `lib/dctl/_lib/workspace/git_worktree.sh` (already done in 15a) |
| `lib/dctl/ws.sh:118-127 devcontainer_exec` | `lib/dctl/commands/ws/exec.sh` |
| `lib/dctl/ws.sh:126,144,196,210,217,219,231` | `lib/dctl/commands/ws/{up,exec,…}.sh` (per round-20 brief) |
| `lib/dctl/ws.sh:266` (bulk-rm path) | `lib/dctl/commands/ws/down.sh` |
| `lib/dctl/image.sh:48-61 discover_image_targets` | `lib/dctl/commands/image/_helpers.sh` |
| `lib/dctl/image.sh:94-280 cmd_image_build` | `lib/dctl/commands/image/build.sh` |
| `lib/dctl/image.sh:149,152,255,279` | `lib/dctl/commands/image/{build,list}.sh` (per round-20 brief) |
| `lib/dctl/init.sh:155-203 generate_cached_devcontainer` | `lib/dctl/commands/init/generate_cache.sh` |
| `lib/dctl/init.sh:237` image-existence check | `lib/dctl/commands/init/generate_cache.sh` |
| `lib/dctl/deploy.sh:67,80,115` | `lib/dctl/commands/deploy/{_discover,apply}.sh` (per round-70 brief) |
| `lib/dctl/test.sh:180` | `lib/dctl/commands/test/run.sh` |
| `lib/dctl/test.sh:30-67 check_pass / check_fail / _print_summary` | `lib/dctl/commands/test/_summary.sh` |
| `lib/dctl/config.sh:279,290 del(.dockerfile)` (legacy migration) | `lib/dctl/_lib/registry/validate.sh` |
| `lib/dctl/auth.sh:12-58` | `lib/dctl/_lib/auth/{gh_token,glab_token,collect_env}.sh` (already done in 15a) |
| `lib/dctl/common.sh:108,113` path-builder helpers | `lib/dctl/_lib/paths.sh` (already done in 15a) |
| `lib/dctl/common.sh:82-84 workspace_label_filter` | `lib/dctl/_lib/workspace/label_filter.sh` (already done in 15a) |

Apply this mapping to every `file:line` mention in `plans/20-*.md`, `plans/40-*.md`, `plans/60-*.md`, `plans/70-*.md`. After the pass, `grep -rn 'lib/dctl/[a-z]*\.sh:' docs/specs/sandbox-runtime/plans/[2-7]*.md` should return zero hits against the flat layout.

### Edit: `tests/dctl_test.bats`, `tests/auth_test.bats`, `tests/config_test.bats`

Update `source` and direct-helper-call paths to point at the new layout. **Behavior-level assertions are unchanged.**

## Out of scope for this round (DO NOT touch)

- Any behavior change inside command verbs. Verb function bodies move verbatim — only the file location changes.
- `lib/dctl/runtime/{common,krun}.sh`, `lib/dctl/lifecycle.sh` — preserved verbatim. Do not touch.
- The Phase 5 `commands/net/` group — round 40's job.
- Containerfile rename or any Phase 7 docs sweep — round 70's job.
- Phase 2's `rt_*` rewire inside the verbs — round 20's job.

## Implementation guidance

### Command-side migration mapping (this round's payload)

| Today | Tomorrow |
|---|---|
| `lib/dctl/ws.sh:129-145 cmd_ws_up` | `lib/dctl/commands/ws/up.sh` |
| `lib/dctl/ws.sh:147-197 cmd_ws_reup` | `lib/dctl/commands/ws/reup.sh` |
| `lib/dctl/ws.sh:118-127 devcontainer_exec` | `lib/dctl/commands/ws/exec.sh` (private helper used by exec/shell/run; the verb wrapper goes in the same file) |
| `lib/dctl/ws.sh:…` `cmd_ws_shell` | `lib/dctl/commands/ws/shell.sh` |
| `lib/dctl/ws.sh:…` `cmd_ws_run` | `lib/dctl/commands/ws/run.sh` |
| `lib/dctl/ws.sh:…` `cmd_ws_status` | `lib/dctl/commands/ws/status.sh` |
| `lib/dctl/ws.sh:…` `cmd_ws_down` | `lib/dctl/commands/ws/down.sh` |
| `lib/dctl/ws.sh` `usage_ws` + main | `lib/dctl/commands/ws/_dispatch.sh` |
| `lib/dctl/image.sh:48-61 discover_image_targets` + `resolve_dockerfile` + `get_image_tag` | `lib/dctl/commands/image/_helpers.sh` |
| `lib/dctl/image.sh:94-280 cmd_image_build` | `lib/dctl/commands/image/build.sh` |
| `lib/dctl/image.sh:…` `cmd_image_list` | `lib/dctl/commands/image/list.sh` |
| `lib/dctl/image.sh` `usage_image` + main | `lib/dctl/commands/image/_dispatch.sh` |
| `lib/dctl/init.sh:…` `cmd_init` (`do` verb) | `lib/dctl/commands/init/do.sh` |
| `lib/dctl/init.sh:…` `select_interactive` | `lib/dctl/commands/init/select_interactive.sh` |
| `lib/dctl/init.sh:155-203 generate_cached_devcontainer` | `lib/dctl/commands/init/generate_cache.sh` |
| `lib/dctl/init.sh` `usage_init` + main | `lib/dctl/commands/init/_dispatch.sh` |
| `lib/dctl/deploy.sh:…` `cmd_deploy_all` | `lib/dctl/commands/deploy/all.sh` |
| `lib/dctl/deploy.sh:…` `cmd_deploy_list` | `lib/dctl/commands/deploy/list.sh` |
| `lib/dctl/deploy.sh:…` `cmd_deploy_plan` | `lib/dctl/commands/deploy/plan.sh` |
| `lib/dctl/deploy.sh:…` `cmd_deploy_apply` | `lib/dctl/commands/deploy/apply.sh` |
| `lib/dctl/deploy.sh:…` `cmd_deploy_reset` | `lib/dctl/commands/deploy/reset.sh` |
| `lib/dctl/deploy.sh:67,80,115` discovery helpers | `lib/dctl/commands/deploy/_discover.sh` |
| `lib/dctl/deploy.sh` `usage_deploy` + main | `lib/dctl/commands/deploy/_dispatch.sh` |
| `lib/dctl/config.sh:…` `cmd_config_register` | `lib/dctl/commands/config/register.sh` |
| `lib/dctl/config.sh:…` `cmd_config_unregister` | `lib/dctl/commands/config/unregister.sh` |
| `lib/dctl/config.sh:…` `cmd_config_list` | `lib/dctl/commands/config/list.sh` |
| `lib/dctl/config.sh:…` `cmd_config_show` | `lib/dctl/commands/config/show.sh` |
| `lib/dctl/config.sh` `usage_config` + main | `lib/dctl/commands/config/_dispatch.sh` |
| `lib/dctl/test.sh:30-67 check_pass / check_fail / _print_summary` | `lib/dctl/commands/test/_summary.sh` |
| `lib/dctl/test.sh:…` `cmd_test` (Phase-2 banner stays at top) | `lib/dctl/commands/test/run.sh` |
| `lib/dctl/test.sh` `usage_test` + main | `lib/dctl/commands/test/_dispatch.sh` |
| `lib/dctl/doctor.sh` per-probe sections (Phase 0) | `lib/dctl/commands/doctor/{crun_libkrun,kvm,libkrun,subid,cgroups,podman_info,network_backend,userns,nested_virt}.sh` |
| `lib/dctl/doctor.sh` `usage_doctor` + main | `lib/dctl/commands/doctor/_dispatch.sh` |
| `bin/dctl` `__dctl_dispatch` fallback to flat files | removed; only `commands/<group>/_dispatch.sh` is dispatched |

### Doctor split detail

Each round-00 probe becomes its own file under `commands/doctor/`. The file defines one function whose name matches the file (e.g. `cmd_doctor_kvm` in `kvm.sh`). `_dispatch.sh`'s `main_doctor` calls each probe function in print order and aggregates results via `_lib/log.sh` + the lifted `check_pass`/`check_fail`/`_print_summary` helpers (which can move to `_lib/` if they end up shared with `commands/test/_summary.sh` — decide during stage 1 planning).

### `lib/dctl/CLAUDE.md` update

Round 15a created this file. Round 15b updates it with:

- The full list of `commands/<group>/` groups (including the not-yet-existing `commands/net/` placeholder slot for round 40).
- The structure-test invariants (`tests/structure_test.bats`) so future contributors know what's enforced.
- Confirmation that `runtime/` and `lifecycle.sh` stay flat (not split until a second backend or until lifecycle.sh exceeds ~300 lines).

## Out of scope for this round (warnings to prevent over-engineering)

- Do **not** adopt full bashly codegen (Ruby toolchain + build step). Copy the directory grammar; the hand-written dispatcher from round 15a is enough.
- Do **not** adopt zsh-style per-function autoload for `_lib/` — already rejected in round 15a's decision record.
- Do **not** split `lifecycle.sh` prematurely. It is new in round 10 and small. Wait until it crosses ~300 lines.
- Do **not** split `runtime/krun.sh` prematurely. One backend; splitting before a second adapter creates abstraction without benefit.

## Acceptance gates (all must pass before stage 4 review approves)

- `make check` passes (lint + bats + format).
- `tests/structure_test.bats` exists and passes, enforcing all four invariants in the Scope section.
- `find lib/dctl/commands -name '*.sh' | wc -l` ≥ 35 (sum of all verb files + `_dispatch.sh` + helper files across 7 groups).
- The flat `lib/dctl/{auth,common,config,deploy,image,init,test,ws,doctor}.sh` files are deleted (`ls lib/dctl/*.sh` shows only `runtime/common.sh`, `runtime/krun.sh`, `lifecycle.sh`).
- The compatibility shim in `__dctl_dispatch` (the fallback to flat files from round 15a) is removed.
- Every existing bats test still passes against the new paths.
- `dctl <group> <verb>` for every existing verb still works end-to-end (smoke-test on the developer's host).
- `grep -rn 'lib/dctl/[a-z]*\.sh:' docs/specs/sandbox-runtime/plans/[2-7]*.md` returns zero hits against the flat layout (re-anchor pass is complete).
- `lib/dctl/CLAUDE.md` is updated with the post-15b layout summary.

## Risks & known gotchas

- **`deploy.sh` is 594 LOC** — biggest single module. Stage 3 may run long. If timeout, abort and re-run as the contingency split (`15b-i` = `ws + image + init + test + doctor`; `15b-ii` = `deploy + config + structure tests + re-anchor`). Mention this in the prex auto-review-loop notes.
- **Re-anchor pass is error-prone.** A pre-reorg `ws.sh:58` may now correspond to two or three post-reorg files (e.g. `commands/ws/up.sh` and `commands/ws/reup.sh` both contain ps-filter code that used to live at `ws.sh:58`). When the mapping is ambiguous, the re-anchor must list **all** post-reorg sites, not pick one arbitrarily.
- **Bats helper sources.** `tests/test_helper.bash` likely `source`s the flat modules. Update it to source the new paths. Skipping this breaks every bats test in one shot.
- **Doctor probe ordering matters.** The print order from round 00 is load-bearing (operator reads the output top-to-bottom). `_dispatch.sh`'s `main_doctor` must call probe functions in the same order as the original `lib/dctl/doctor.sh` printed them.
- **`commands/<group>/_dispatch.sh` and `cmd_<group>_<verb>` naming.** The structure test enforces these strictly. A typo in one filename (e.g. `commands/ws/reUp.sh` instead of `reup.sh`) silently breaks the dispatcher routing. The structure test catches that — verify it runs in CI.

## Plan-file cleanup (Codex must perform in stage 3, as part of the implementation commit)

1. Delete this file: `docs/specs/sandbox-runtime/plans/15b-command-tree-extraction.md`.
2. Update `docs/specs/sandbox-runtime/plans/README.md`: this round's row `Status` → `Done — <commit-sha> — <date>`.
3. Promote durable content:
   - The command-tree layout is documented permanently in `lib/dctl/CLAUDE.md` (updated by this round).
   - The structure-test invariants live permanently in `tests/structure_test.bats`.
4. Update `docs/specs/sandbox-runtime/IMPLEMENTATION-PLAN.md`: tick the Phase 1.5b row in the `## Per-round briefs` section.
