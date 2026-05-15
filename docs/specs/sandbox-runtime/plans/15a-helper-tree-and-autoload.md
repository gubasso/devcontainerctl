# Phase 15a — Helper tree + autoload + bin/dctl rewrite (prex task brief)

> Status: Pending
> Companion docs (Codex must read these in stage 1):
> - [docs/specs/sandbox-runtime/IMPLEMENTATION-PLAN.md](../IMPLEMENTATION-PLAN.md) (master overview)
> - `~/.dotfiles/bash/.config/bash/lib/autoload.bash:6-14` — the inspiration for the autoload primitives
> - `~/.dotfiles/bash/.config/bash/CLAUDE.md:14-19` — the orientation-table style to mirror
> - [bashly `commands_dir` convention](https://bashly.dev/configuration/command/) — one subcommand per file
> - [Augment — AGENTS.md sizing](https://www.augmentcode.com/blog/how-to-write-good-agents-dot-md-files), [DEV — coding agents as first-class consideration](https://dev.to/somedood/coding-agents-as-a-first-class-consideration-in-project-structures-2a6b), [Aider repo map](https://aider.chat/docs/repomap.html) — AI-friendliness rationale
> Depends on: [`10-runtime-adapter-and-lifecycle.md`](10-runtime-adapter-and-lifecycle.md) — must be `Done`. `lib/dctl/runtime/{common,krun}.sh` and `lib/dctl/lifecycle.sh` exist and are preserved verbatim through this round.
> Output of this round: `lib/dctl/_lib/` helper tree exists, `bin/dctl` is rewritten around `__dctl_dispatch`, all helper functions live in one-function-per-file modules. `commands/` extraction is round `15b`'s job.

## Task

Phase 1.5 part A. Extract every library-style helper currently buried inside `lib/dctl/common.sh`, `lib/dctl/auth.sh`, the helpers section of `lib/dctl/ws.sh`, and `lib/dctl/init.sh` into a new `lib/dctl/_lib/` tree where every file defines exactly one function (helper sweet spot 30–80 lines). Rewrite `bin/dctl` to replace the eager `source` block at `bin/dctl:14-20` with `__dctl_dispatch "$@"` plus three eager `_lib/` sources. Land `lib/dctl/CLAUDE.md` (≤ 150 lines) as per-directory guidance. **Do not** touch command modules (`ws.sh`, `image.sh`, `init.sh`, `deploy.sh`, `config.sh`, `test.sh`, `doctor.sh`) beyond what's needed to keep their helper imports working — those move in round `15b`.

This round is a **pure rename + extract pass** with no behavior change. Existing bats tests must still pass against the new helper paths.

## Preconditions (must already be true on `develop`)

- Round `10` (runtime-adapter-and-lifecycle) is `Done`. `lib/dctl/runtime/{common,krun}.sh` and `lib/dctl/lifecycle.sh` exist.
- `make check` is green.
- Current `lib/dctl/` flat layout is intact: `common.sh`, `auth.sh`, `config.sh`, `deploy.sh`, `image.sh`, `init.sh`, `test.sh`, `ws.sh`, `doctor.sh` (Phase 0).

## Scope (in this round)

### New: `lib/dctl/_lib/` helper tree

One helper function per file. Filename = function name. Files starting with `_` are private to their directory and not registered as commands.

- `_lib/source.sh` — `__dctl_require <path>` (source-once guarded on `_DCTL_LOADED_<path>`) and `__dctl_autoload_register <verb> <file>` primitives. Port and trim from `~/.dotfiles/bash/.config/bash/lib/autoload.bash:6-14`.
- `_lib/log.sh` — `log`, `warn`, `err`, `require_cmd` (extracted from `lib/dctl/common.sh:31-47`).
- `_lib/paths.sh` — XDG var declarations + `workspace_*_path` helpers (extracted from `lib/dctl/common.sh:7-114`).
- `_lib/fzf.sh` — `_fzf_pick` (extracted from `lib/dctl/common.sh:49-68`).
- `_lib/workspace/canonical_name.sh` — `resolve_canonical_project_name` (was `common.sh:116-149`).
- `_lib/workspace/resolve_config.sh` — `resolve_devcontainer_config` (was `common.sh:196-259`).
- `_lib/workspace/label_filter.sh` — `workspace_label_filter` (was `common.sh:82-84`).
- `_lib/workspace/sibling.sh` — sibling-discovery helper from `common.sh` (the remaining `common.sh:150-195` block; split by function).
- `_lib/workspace/git_worktree.sh` — `collect_git_worktree_mounts` (was `ws.sh:84-104`).
- `_lib/registry/file.sh`, `_lib/registry/lookup_manifest.sh`, `_lib/registry/lookup_discovery.sh`, `_lib/registry/validate.sh`, `_lib/registry/validate_manifest.sh` — extracted from `lib/dctl/config.sh` (the validation/registry-IO helpers; not the verb implementations).
- `_lib/json/strip_comments.sh` — `_strip_jsonc_comments` (was `init.sh:62-…`).
- `_lib/json/merge_configs.sh` — `merge_two_configs` (was `init.sh:66-…`). **This is the file the merge-logic extension from round `10` lives in** — verify the `runArgs`/`workspaceMount`/`workspaceFolder` handling lands here unchanged.
- `_lib/auth/gh_token.sh` — `_extract_gh_token` (was `auth.sh:12-36`).
- `_lib/auth/glab_token.sh` — `_extract_glab_token` (was `auth.sh:38-58`).
- `_lib/auth/collect_env.sh` — auth-env aggregator from `auth.sh` (the remaining block).
- `_lib/term/collect_env.sh` — terminal-env aggregator from `ws.sh:106-116`.

The `_lib/auth/ephemeral_creds.sh` placeholder is **not** created here — Phase 4 (round `40`) creates it.

### Rewrite: `bin/dctl`

Replace the eager `source` block at `bin/dctl:14-20` with:

```sh
source "${DCTL_LIB_DIR}/_lib/source.sh"
__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_dispatch "$@"
```

`__dctl_dispatch` is ~30 lines, lives in `_lib/source.sh` (or a `_lib/dispatch.sh` peer — choose during stage 1 planning). It routes `<group>` → `__dctl_require commands/<group>/_dispatch.sh; main_<group> "$@"`. Until round `15b` lands the `commands/` tree, the dispatcher's `commands/<group>/_dispatch.sh` calls will miss — so this round **keeps the existing flat `ws.sh`/`image.sh`/etc. in place** and the dispatcher falls back to sourcing them if the new layout is absent. The fallback is removed in round `15b`.

Three eager sources only (per the structure-test invariant added in round `15b`): `_lib/source.sh`, `_lib/log.sh`, `_lib/paths.sh`. Everything else is lazy.

### New: `lib/dctl/CLAUDE.md`

≤ 150 lines, mirroring `~/.dotfiles/bash/.config/bash/CLAUDE.md`. Per-directory orientation: what goes where, the naming rules, the sourcing model. Include the "What / Where" table for `_lib/`, `commands/`, `runtime/`, `lifecycle.sh`.

### Edit: `docs/CLAUDE.md` Quick Orientation block

Refresh the entry-level orientation to the new layout. Add the table from IMPLEMENTATION-PLAN.md §1.5 step 8 — *Internal helpers → `lib/dctl/_lib/<topic>/<name>.sh`*, etc.

## Out of scope for this round (DO NOT touch)

- The `lib/dctl/commands/<group>/` extraction — round `15b`.
- The `tests/structure_test.bats` file and the plan re-anchor pass — round `15b`.
- Any behavior change inside helper functions. This is a pure move + one-function-per-file split.
- The flat `lib/dctl/{common,auth,ws,init,image,deploy,config,test,doctor}.sh` files **stay in place** this round; their helper-function definitions are deleted as those helpers move to `_lib/`, but the verb implementations remain. The flat files are deleted in round `15b` after the command tree is extracted.
- `lib/dctl/runtime/{common,krun}.sh` and `lib/dctl/lifecycle.sh` are preserved verbatim — they already follow the one-function-per-file ethos.

## Implementation guidance

### Sourcing model (decision recorded — do not revisit)

**Chosen: source-once-guarded, group-lazy + verb-lazy.** `__dctl_require <path>` guards on a `_DCTL_LOADED_<path>` shell var (normalize `/` → `_`). `dctl ws up` sources 3 eager files + `commands/ws/_dispatch.sh` + `commands/ws/up.sh` + the helpers `up.sh` declares it needs — roughly 6–10 files per invocation.

**Rejected (do not implement):**
- Git-style PATH dispatch (`dctl-ws-up` per file). Doubles process-startup cost; loses single `set -euo pipefail` shell state.
- Full per-function autoload (~50 stubs at startup). 50 `eval` calls per invocation for no benefit at the dispatcher level — autoload pays off in interactive shells (the `~/.dotfiles/bash` use case), not single-shot CLIs.

### Naming conventions (enforced by review, not tooling this round)

- Command files: filename = verb name; defines exactly one `cmd_<group>_<verb>` function.
- Helper files: filename = function name; defines exactly one function. `__` prefix = internal-only; plain name = exported library API.
- Files starting with `_` (`_dispatch.sh`, `_helpers.sh`) are private to their directory and not registered as commands.
- Soft cap: 200 lines/file. Hard cap: 500 lines/file. Files crossing the hard cap fail review.
- Directory depth ≤ 3 levels under `lib/dctl/` (`lib/dctl/_lib/workspace/git_worktree.sh` is fine; deeper paths burn tokens on every path mention).
- Floor: ≥ 30 lines per helper file. A 5-line file is worse than living in a 50-line peer.

### Helper-side migration mapping (this round only)

| Today | Tomorrow |
|---|---|
| `lib/dctl/common.sh:31-47 log/warn/err/require_cmd` | `lib/dctl/_lib/log.sh` |
| `lib/dctl/common.sh:7-114` (XDG + `workspace_*_path`) | `lib/dctl/_lib/paths.sh` |
| `lib/dctl/common.sh:49-68 _fzf_pick` | `lib/dctl/_lib/fzf.sh` |
| `lib/dctl/common.sh:82-84 workspace_label_filter` | `lib/dctl/_lib/workspace/label_filter.sh` |
| `lib/dctl/common.sh:116-149 resolve_canonical_project_name` | `lib/dctl/_lib/workspace/canonical_name.sh` |
| `lib/dctl/common.sh:150-195` sibling helpers | `lib/dctl/_lib/workspace/sibling.sh` |
| `lib/dctl/common.sh:196-259 resolve_devcontainer_config` | `lib/dctl/_lib/workspace/resolve_config.sh` |
| `lib/dctl/auth.sh:12-36 _extract_gh_token` | `lib/dctl/_lib/auth/gh_token.sh` |
| `lib/dctl/auth.sh:38-58 _extract_glab_token` | `lib/dctl/_lib/auth/glab_token.sh` |
| `lib/dctl/auth.sh:60-…` auth-env aggregator | `lib/dctl/_lib/auth/collect_env.sh` |
| `lib/dctl/ws.sh:84-104 collect_git_worktree_mounts` | `lib/dctl/_lib/workspace/git_worktree.sh` |
| `lib/dctl/ws.sh:106-116` terminal-env aggregator | `lib/dctl/_lib/term/collect_env.sh` |
| `lib/dctl/init.sh:62-… _strip_jsonc_comments` | `lib/dctl/_lib/json/strip_comments.sh` |
| `lib/dctl/init.sh:66-… merge_two_configs` (with Phase-1 merge-logic extension) | `lib/dctl/_lib/json/merge_configs.sh` |
| `lib/dctl/config.sh` validation/registry-IO helpers (NOT the verb impls) | `lib/dctl/_lib/registry/*.sh` (5 files) |
| `bin/dctl:14-20` eager-source block | replaced with `__dctl_require _lib/log.sh; __dctl_require _lib/paths.sh; __dctl_dispatch "$@"` |

Each row corresponds to a single new file. Each new file contains exactly one function (plus comments). When a helper currently calls another helper, both must be present in `_lib/` and the caller `__dctl_require`s the callee at the top.

### Compatibility shim for round 15a (deleted in 15b)

Until `commands/` exists (round `15b`), the existing flat `lib/dctl/{auth,common,config,deploy,image,init,test,ws,doctor}.sh` must still source the new `_lib/` modules instead of defining the helpers inline. The simplest path: replace each removed helper definition in the flat file with a `__dctl_require _lib/<...>.sh` line at the top.

The `__dctl_dispatch` function in `_lib/source.sh` checks for `commands/<group>/_dispatch.sh`; if absent, falls back to `source "${DCTL_LIB_DIR}/<group>.sh"; main_<group> "$@"`. This fallback is **removed** in round `15b` once every group lives under `commands/`.

## Acceptance gates (all must pass before stage 4 review approves)

- `make check` passes (lint + bats + format).
- `find lib/dctl/_lib -name '*.sh' | wc -l` ≥ 17 (one file per row of the migration mapping, plus `source.sh`).
- Every file in `lib/dctl/_lib/` defines **at most one** function (`grep -c '^[a-zA-Z_]*[a-zA-Z_0-9]*[[:space:]]*()' lib/dctl/_lib/**/*.sh` shows 1 per file).
- Every file in `lib/dctl/_lib/` is ≤ 200 lines (`wc -l lib/dctl/_lib/**/*.sh` — flag any > 200 for splitting).
- `bin/dctl` sources only `_lib/source.sh`, `_lib/log.sh`, `_lib/paths.sh` at startup. Other modules are `__dctl_require`-loaded on demand.
- Every existing bats test still passes (helpers are reachable via the new paths through the shim).
- `dctl ws up`, `dctl image build`, `dctl init`, `dctl deploy`, `dctl config`, `dctl test`, `dctl doctor` all still work end-to-end on the developer's host (smoke-tested manually if no bats coverage exists).
- `lib/dctl/CLAUDE.md` exists and is ≤ 150 lines, with the per-directory orientation block + the naming rules + the sourcing-model summary.
- `docs/CLAUDE.md` Quick Orientation block lists the new layout.

## Risks & known gotchas

- **Helper interdependencies.** `resolve_devcontainer_config` calls into `workspace_label_filter`, `_strip_jsonc_comments`, etc. When extracting, each new file must `__dctl_require` its dependencies. Stage-1 planning must inventory the call graph before any extraction starts; missing a `__dctl_require` causes silent failure with `command not found` at runtime.
- **The merge-logic extension from round 10.** That extension lives inside `merge_two_configs` (previously `lib/dctl/init.sh:66-…`). Extraction must preserve the `runArgs`/`workspaceMount`/`workspaceFolder` first-class-merge behavior. Add a smoke assertion if `tests/dctl_test.bats` doesn't already cover it.
- **`bin/dctl --help` and version output.** If those paths source modules eagerly today, the rewrite must preserve their behavior. The `__dctl_dispatch` must handle `--help` / `--version` / no-args without sourcing any group.
- **Round 15b deletes the flat files.** The compatibility shim in this round (flat files `__dctl_require`-ing `_lib/`) is intentionally throw-away. Don't put effort into making it pretty.
- **Helper extraction floor.** A 5-line helper file is worse than living in a 50-line peer (per the design rationale). If extraction produces a < 30-line file, merge it into a sibling helper that uses it. Track exceptions explicitly.

## Plan-file cleanup (Codex must perform in stage 3, as part of the implementation commit)

1. Delete this file: `docs/specs/sandbox-runtime/plans/15a-helper-tree-and-autoload.md`.
2. Update `docs/specs/sandbox-runtime/plans/README.md`: this round's row `Status` → `Done — <commit-sha> — <date>`.
3. Promote durable content:
   - The naming conventions, sourcing-model decision, and "What / Where" table live permanently in the new `lib/dctl/CLAUDE.md` and (entry-point summary) `docs/CLAUDE.md`.
4. Update `docs/specs/sandbox-runtime/IMPLEMENTATION-PLAN.md`: tick the Phase 1.5a row in the `## Per-round briefs` section.
