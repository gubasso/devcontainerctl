# Sandbox-runtime per-round briefs

> Status: Active (refactor in progress)
> Companion: [../IMPLEMENTATION-PLAN.md](../IMPLEMENTATION-PLAN.md) — the slim overview (invariants, architecture, verification, out-of-scope).

These are `/prex` **task briefs**. Each file is consumed once by a single `/prex` invocation, which runs Codex-plans → Claude-reviews → Codex-implements → Claude-reviews. See `~/.dotfiles/claude/.claude/skills/prex/SKILL.md` for the underlying workflow contract.

The briefs are **ephemeral**: after a round merges, its brief is deleted and any durable content (long-term spec text, architecture notes, security model) is promoted to its permanent home elsewhere in the repo. When all rows below show `Done`, delete this README and the empty `plans/` directory.

## Invocation form

Each brief is inlined into `$ARGUMENTS`:

```sh
/prex -ar "$(cat docs/specs/sandbox-runtime/plans/00-preflight-doctor.md)"
```

Recommended flags:

- **`-ar`** (auto-approve + review-loop) for the heavy rounds: `10`, `15b`, `60`, `70`.
- **`-a`** (auto-approve only) for the modest rounds: `00`, `15a`, `20`, `40`.

The `-ar` review-loop adds an extra Codex review pass after stage 4, which is worth the cost on rounds that touch many files or introduce new core modules.

## Run order

Sequential by numeric prefix: `00` → `10` → `15a` → `15b` → `20` → `40` → `60` → `70`.

The cross-round dependencies are encoded in each brief's `Depends on:` header. **Do not start a round until the prior round's brief is deleted and its row below shows `Done`.** That deletion is the cleanup contract Codex follows in the brief's `## Plan-file cleanup` section.

## Status

| # | Brief | Status | Commit | Notes |
|---|---|---|---|---|
| 00 | [preflight-doctor](00-preflight-doctor.md) | Pending | — | Host preflight + `dctl doctor` + `docs/INSTALL.md`. |
| 10 | [runtime-adapter-and-lifecycle](10-runtime-adapter-and-lifecycle.md) | Pending | — | `lib/dctl/runtime/{common,krun}.sh` + `lib/dctl/lifecycle.sh`. |
| 15a | [helper-tree-and-autoload](15a-helper-tree-and-autoload.md) | Pending | — | Extract `lib/dctl/_lib/`; rewrite `bin/dctl`; new `lib/dctl/CLAUDE.md`. |
| 15b | [command-tree-extraction](15b-command-tree-extraction.md) | Pending | — | Extract `commands/{ws,image,init,test,doctor,deploy,config}/`; add `tests/structure_test.bats`; re-anchor remaining briefs. |
| 20 | [ws-and-image-adapter-rewire](20-ws-and-image-adapter-rewire.md) | Pending | — | Route `dctl ws` + `dctl image` through `rt_*`. |
| 40 | [tier0-hygiene-and-egress](40-tier0-hygiene-and-egress.md) | Pending | — | Tier 0 hygiene + `commands/net/*` + in-VM nftables. |
| 60 | [test-suite](60-test-suite.md) | Pending | — | Bats refactor + 3 new test files. |
| 70 | [renames-and-docs-sweep](70-renames-and-docs-sweep.md) | Pending | — | Schema + Dockerfile→Containerfile + repo-wide docs sweep + final grep gate. |

## Contingency splits

If a round hits the 10-minute stage-3 timeout, split as follows and run the halves as two consecutive `/prex` rounds (add new rows above for status tracking):

- **15b → 15b-i + 15b-ii**: 15b-i covers `commands/{ws,image,init,test,doctor}/` extraction; 15b-ii covers `commands/{deploy,config}/` + `tests/structure_test.bats` + the plan re-anchor pass. `deploy.sh` is 594 LOC, the biggest single module.
- **70 → 70a + 70b**: 70a covers code-side (schema + Containerfile renames + shell rewires + devcontainer/systemd); 70b covers docs sweep + legacy `spec/` set + final grep gate.
- **40 → 40a + 40b**: 40a covers Phase 4 (Tier 0 hygiene + ephemeral creds); 40b covers Phase 5 (egress allowlist).

If a contingency split is invoked, edit this README's status table to add the sub-rows and update the corresponding brief's `Depends on:` headers.

## Cleanup convention

Each brief includes a `## Plan-file cleanup` section instructing Codex (stage 3, as part of the implementation commit) to:

1. Delete the brief file (`docs/specs/sandbox-runtime/plans/<NN>-<topic>.md`).
2. Update this README row: `Status` → `Done — <commit-sha> — <date>`.
3. Promote any durable content produced by the round to its permanent home (e.g. `docs/INSTALL.md`, `docs/SECURITY.md`, `lib/dctl/CLAUDE.md`).
4. Tick the corresponding bullet in `../IMPLEMENTATION-PLAN.md`'s `## Per-round briefs` section.

After all eight rows show `Done`:

1. Delete this README.
2. Remove the empty `plans/` directory.
3. Update the bottom of `../IMPLEMENTATION-PLAN.md` to mark the whole refactor complete (move the `## Per-round briefs` section into a `## Refactor history` footnote).
