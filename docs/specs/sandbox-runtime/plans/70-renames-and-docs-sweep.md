# Phase 70 — Schema, file renames, docs sweep, final grep gate (prex task brief)

> Status: Pending
> Companion docs (Codex must read these in stage 1):
> - [docs/specs/sandbox-runtime/SPEC.md](../SPEC.md) (§4.1, §5.4)
> - [docs/specs/sandbox-runtime/DECISION.md](../DECISION.md), [docs/specs/sandbox-runtime/DECISION-LINUX.md](../DECISION-LINUX.md)
> - [docs/specs/sandbox-runtime/IMPLEMENTATION-PLAN.md](../IMPLEMENTATION-PLAN.md) (master overview)
> - [`spec/README.md`](../../../spec/README.md) and the implemented-feature spec set (referenced from `docs/CLAUDE.md`).
> Depends on: [`60-test-suite.md`](60-test-suite.md) — must be `Done`. The full bats suite passes including the new adapter/auth/net coverage.
> Output of this round: the project reads as if Podman were the only runtime that ever existed. The schema declares `runtime` / `network.allow`. Build files are `Containerfile`. The final `Docker(file)?` grep gate is empty modulo the documented whitelist.

## Task

Complete the podman-first end state across every file in the repo. Extend `schemas/compose.schema.yaml` with the `runtime` + `runtime.resources` + `network.allow` keys. Rename `images/<name>/Dockerfile` → `images/<name>/Containerfile` (4 files via `git mv`). Update every shell path-builder / existence-check / variable name. Sweep all docs (top-level, sub-docs, legacy `spec/` set, devcontainer configs, systemd, Makefile). Enforce a final `Docker(file)?` grep gate. After this round, zero `docker` / `Docker` references survive outside (a) factual security-history CVE references and (b) the upstream `build.dockerfile` schema key (kept for devcontainer.json compatibility, value flipped to `"Containerfile"`).

This round is large but **mostly mechanical**. Contingency split: if stage 3 hits the timeout, split into `70a` (code-side: schema + Containerfile renames + shell rewires + devcontainer/systemd) and `70b` (docs sweep + legacy `spec/` + final grep gate). See `plans/README.md`.

## Preconditions (must already be true on `develop`)

- Round `60` is `Done`. The full bats suite passes including the new adapter/auth/net tests.
- `make check` is green on `develop`.
- `lib/dctl/commands/` + `lib/dctl/_lib/` layout is in place from round 15b.
- Tier 0 hygiene + egress allowlist are on the default path from round 40.

## Scope (in this round)

### 1. Extend `schemas/compose.schema.yaml`

Add optional keys:

- `runtime: krun` (currently the only valid value; future-compat for `gvisor` / `kata-ch`).
- `runtime.resources.memory_mib` (default 4096), `runtime.resources.cpus` (default 2).
- `network.allow` (list of host strings; matches the round-40 `commands/net/*` consumer).

`commands/init/_generate_cache.sh` (rewired in round 20) already emits the runtime overlay; this round's schema addition makes the manifest-level override path official.

### 2. Rename build files: `images/<name>/Dockerfile` → `images/<name>/Containerfile`

Four files via `git mv` to preserve history: `agents`, `python-dev`, `rust-dev`, `zig-dev`. Podman/Buildah auto-discovers `Containerfile`, so `podman build <ctx>` works without `-f`.

Shell-side updates:

- `lib/dctl/_lib/paths.sh` — `Dockerfile` → `Containerfile` in path-builder helpers.
- `lib/dctl/commands/deploy/_discover.sh` and `commands/deploy/apply.sh` — `Dockerfile` → `Containerfile`.
- `lib/dctl/commands/image/_helpers.sh` — existence check `Dockerfile` → `Containerfile`. Rename the `resolve_dockerfile()` function + `$dockerfile_path` variable → `resolve_containerfile()` / `$containerfile_path`. The helper **file** itself becomes `resolve_containerfile`-named per the one-function-per-file convention if it's currently in a file named after the function — otherwise leave the filename.
- `lib/dctl/commands/test/run.sh` — call `resolve_containerfile`.
- `tests/dctl_test.bats` — ~16 references including `touch ".../Dockerfile"` test setup, `.bak.` backup-suffix assertions (which become `Containerfile.bak.<timestamp>` automatically since the suffix is path-derived), and test descriptions ("make install puts Containerfiles in DATA_DIR/images", etc.).
- **Leave the legacy YAML registry key `dockerfile`** in `lib/dctl/_lib/registry/validate.sh` and `tests/config_test.bats` alone — that's the deprecated schema key being explicitly rejected by the migration logic; renaming would break the deprecation path. Add a short source comment confirming the legacy key is intentionally preserved.

### 3. Top-level docs sweep

Remove every remaining `docker`/`Docker` reference; the project reads as if Podman were the only runtime that ever existed:

- `README.md` — rewrite install / quickstart / CLI examples / XDG layout sections around Podman + libkrun. Replace any "powered by Docker" framing with "powered by Podman + libkrun (rootless microVMs)".
- `docs/QUICKSTART.md` — finalize the openSUSE Tumbleweed install path. Round 00 already cleaned the Prerequisites block; this round expands with `podman`, `slirp4netns`/`pasta`, `crun` (+LIBKRUN), `libkrun`, `libkrunfw`; minimum versions; `kvm` group note; `dctl doctor` first-run check. Cross-link `docs/INSTALL.md`.
- `docs/ARCHITECTURE.md` — re-do the security-boundary section in light of microVM isolation; rewrite the §"Advanced Configuration — Custom Containerfile per Project" block; flip the upstream-schema example value `"dockerfile": "Dockerfile"` to `"dockerfile": "Containerfile"` (the **key** name is upstream Microsoft schema, the **filename** value is ours); drop the markdown ` ```dockerfile ` fence language tag in favor of ` ```containerfile ` (or just plain text); note that `seccomp-bwrap.json` and `apparmor=unconfined` are no longer load-bearing under microVM isolation (Tier 3 cleanup deferred per [SPEC.md §5.4](../SPEC.md)).
- `docs/CLAUDE.md` — round 00 partially cleaned the Quick Orientation block; this round finalizes: replace any surviving "Pre-built Docker images" tagline → "Pre-built OCI images (Podman + libkrun)"; ensure the "Quick Orientation" block includes `lib/dctl/runtime/` and `lib/dctl/lifecycle.sh`; rename "managed Dockerfiles" → "managed Containerfiles" in the `images/` line if not already done.
- `docs/WORKFLOW-COMPARISON.md` — rewrite or retire entirely if its purpose was comparing the legacy Docker-based flow to alternatives. If kept, replace all `docker buildx build --load -t devimg/... ~/dockerfiles/...` examples with `podman build -t devimg/... ~/containerfiles/...`.
- `docs/INSTALL.md` (created in round 00) — audit and finalize: host packages, KVM group membership, smoke-test commands, OBS `Virtualization` repo enable step, references footer.
- `docs/SECURITY.md` (created in round 40) — audit for any `Docker` references; should already be clean but verify.

### 4. Sub-docs sweep

- `devcontainers/README.md` — rewrite layer/composition narrative around Podman; drop Docker mentions; update `devcontainers/README.md:90` to reflect the round-10 merge-logic extension (`runArgs` / `workspaceMount` / `workspaceFolder` are now first-class merged keys).
- `slides/slides.md` — bring slides in line with the podman-first project framing; drop any "powered by Docker" slide.
- `lib/dctl/CLAUDE.md` (created in round 15a, updated in 15b) — audit for Docker references; expected to be clean already.

### 5. Legacy `spec/` set sweep

The implemented-feature spec docs referenced from `docs/CLAUDE.md`:

- `git mv spec/40-dockerfile-hierarchy.md spec/40-containerfile-hierarchy.md`.
- Update every cross-reference: `spec/README.md` (two entries), `docs/ARCHITECTURE.md` (the link to the renamed file), and any other in-repo link to the old filename.
- Bulk-replace `Dockerfile` → `Containerfile` in all `spec/*.md` files; rename the pseudo-code helper `resolve_dockerfile(target)` → `resolve_containerfile(target)` in `spec/40-containerfile-hierarchy.md` to match the new shell function name.
- Audit `spec/45-devcontainer-metadata-extraction.md`, `spec/35-deploy.md`, `spec/30-templates.md`, `spec/20-devcontainer-resolution.md`, `spec/99-acceptance-criteria.md`, `spec/00-resolution-model.md`, `spec/90-implementation-impact.md` for any remaining `docker` mentions (e.g. "docker image", "docker run") and rewrite to `podman` equivalents.

### 6. devcontainers/* configs

- `devcontainers/agents/devcontainer.json:87` — update the inline comment `images/agents/Dockerfile narrows passwordless sudo` → `images/agents/Containerfile narrows passwordless sudo`.
- Audit every `devcontainers/*/devcontainer.json` for `Dockerfile` mentions in `build.dockerfile` **values**. The **value** flips to `"Containerfile"`; the **key** stays as the upstream Microsoft schema `dockerfile`.
- Audit every `devcontainers/*/devcontainer.json` for `Dockerfile.bak` and similar legacy artifacts.

### 7. Systemd / Makefile

- `Makefile` — verify no `Dockerfile` / `docker` references; update if found.
- `systemd/*.service`, `systemd/*.timer` — drop any unit comments or `Description=` text mentioning Docker. The weekly rebuild service runs `dctl image build --all` (runtime-agnostic; no change needed beyond text).

### 8. Remove dead code

- Any container-CLI shell-outs (`docker ...`, `nerdctl ...`, `devcontainer up/exec ...`) surviving outside `lib/dctl/runtime/krun.sh` → bug. Repo-wide check: `grep -rn 'docker\|devcontainer up\|devcontainer exec' lib/ bin/` → expected output is empty.
- Any legacy build-tool env-var references (`DOCKER_BUILDKIT`, `DOCKER_HOST`, `BUILDKIT_*`) inside `images/<name>/Containerfile`, `bin/dctl`, `lib/dctl/_lib/**`, or `lib/dctl/commands/**` → drop.
- Any `seccomp-bwrap.json` / `apparmor=unconfined` references in active code or default profiles → move under the opt-in `agents-permissive` profile only (already done in round 40 if bwrap-dependent agents required it); defaults are `agents-strict`.

### 9. Final grep gate (CI-enforceable)

```sh
! grep -rniE 'docker(file)?' \
    --include='*.sh' --include='*.bats' --include='*.md' \
    --include='*.yaml' --include='*.yml' --include='*.json' \
    --include='Makefile' \
    . | grep -v '/.git/' \
    | grep -vE '(build\.dockerfile|CVE-2025-9074|Leaky Vessels|outcoldman|firedocker)'  # whitelist
```

Empty output is the pass condition. The whitelist documents the **only** acceptable surviving mentions: the upstream `build.dockerfile` schema key (kept for devcontainer.json compatibility) and factual CVE-history references where the affected vendor must be named for accuracy. Anything else surfacing must be fixed before round 70 closes.

Wire this gate into CI (a new Makefile target `check-no-docker` invoked from `make check`, or a pre-commit hook entry).

## Out of scope for this round (DO NOT touch)

- Any source-code behavior change. This is a docs/schema/rename round.
- New runtime backends (`gvisor`, `kata-ch`) — schema future-compat is the only nod; no implementation.
- The `runtime.resources` field becoming honored at the manifest level — round 20 hardcoded the defaults; this round adds the schema; honoring overrides is a follow-up task (track in `IMPL-NOTES.md` or as a new tsk).

## Implementation guidance

### Order of operations within stage 3

1. Schema first (smallest, validates the rest).
2. `git mv` the four Dockerfiles.
3. Shell-side path/variable/function renames.
4. Test fixtures.
5. Docs (top-level → sub-docs → legacy spec).
6. devcontainer configs.
7. systemd/Makefile.
8. Dead-code grep.
9. Final grep gate; iterate until empty.
10. Plan-file cleanup.

### `git mv` semantics

Use `git mv` (not `mv && git add`) for the Dockerfile renames so `git log --follow` continues to work for image history.

### Bats fixture updates

`tests/dctl_test.bats` has ~16 references. Update both the test fixture setup (`touch ".../Dockerfile"` → `touch ".../Containerfile"`) and the assertion strings ("Dockerfiles in DATA_DIR/images" → "Containerfiles in DATA_DIR/images"). The `.bak.` backup-suffix assertions need only the prefix updated; the timestamp suffix is path-derived.

### Whitelist hygiene

The grep-gate whitelist is intentionally narrow:
- `build.dockerfile` — upstream Microsoft schema key, kept for compatibility.
- `CVE-2025-9074`, `Leaky Vessels`, `outcoldman`, `firedocker` — factual CVE history / vendor names that cannot be rewritten without losing meaning.

If a new factual reference must be added (e.g. a future CVE), expand the whitelist explicitly in this gate's regex and document why in the source comment above the grep.

### Legacy spec/ filename rename impact

Many things link to `spec/40-dockerfile-hierarchy.md`. Use `git grep -l 'spec/40-dockerfile-hierarchy.md' | xargs sed -i 's|spec/40-dockerfile-hierarchy.md|spec/40-containerfile-hierarchy.md|g'` (or equivalent) to catch every link. Verify the link rewriter in any docs renderer (mermaid, mkdocs) still resolves.

## Acceptance gates (all must pass before stage 4 review approves)

- `make check` passes (lint + bats + format).
- `tests/structure_test.bats` (the round-15b file-layout invariants) passes.
- The final grep gate (above) returns empty output.
- Schema validation passes: a manifest with `runtime: krun`, `runtime.resources.memory_mib: 8192`, `runtime.resources.cpus: 4`, `network.allow: [foo.example]` is accepted; invalid values (`runtime: docker`) are rejected.
- All four `images/*/Containerfile` files exist; the corresponding `Dockerfile` files do not.
- `dctl image build --all` builds every image (proves the rename + path-builder rewires hold).
- `dctl init && dctl deploy` against the `general` manifest produces a cached `devcontainer.json` referencing `Containerfile`, not `Dockerfile`.
- `spec/40-containerfile-hierarchy.md` exists; `spec/40-dockerfile-hierarchy.md` does not. All in-repo links to the old path are updated.
- `grep -rn 'docker\|devcontainer up\|devcontainer exec' lib/ bin/` returns zero hits.
- `make install-systemd` still works (the unit text was updated but the target is runtime-agnostic).
- The 10-point verification gate in `IMPLEMENTATION-PLAN.md` §Verification passes end-to-end on the developer's KVM host.

## Risks & known gotchas

- **The grep gate is sensitive to encoding.** A Unicode dash in `Docker—file` would slip through `Docker(file)?`. Prefer broader regex with a small documented whitelist, but keep the whitelist small.
- **Legacy `dockerfile` registry key.** The migration logic in `_lib/registry/validate.sh` explicitly rejects the legacy `dockerfile` YAML key. Do **not** rename either the rejection code or the test that exercises it — that's the deprecation path. The grep gate's whitelist must allow this specific legacy mention.
- **`build.dockerfile` schema key.** The whitelist permits exactly the upstream-schema string. Audit each surviving mention to make sure it's actually the schema key and not stale prose.
- **Renaming `resolve_dockerfile` impacts test mocks** in `tests/dctl_test.bats`. Round 60 may not have updated these. Grep + update in this round.
- **`docs/ARCHITECTURE.md` mermaid diagrams** — if any diagram label references `Dockerfile`, the round-60 mermaid-compat rule (no special chars in labels) applies. Verify the rendered diagram in nvim before declaring done.
- **`docs/WORKFLOW-COMPARISON.md`** may be retired entirely. If retired, remove cross-references in `docs/CLAUDE.md` and `README.md`.

## Plan-file cleanup (Codex must perform in stage 3, as part of the implementation commit)

1. Delete this file: `docs/specs/sandbox-runtime/plans/70-renames-and-docs-sweep.md`.
2. Update `docs/specs/sandbox-runtime/plans/README.md`: this round's row `Status` → `Done — <commit-sha> — <date>`.
3. Promote durable content:
   - The schema extensions are durable inside `schemas/compose.schema.yaml`.
   - The grep-gate command lives permanently in `Makefile` (as the `check-no-docker` target) and/or `.pre-commit-config.yaml`.
4. Update `docs/specs/sandbox-runtime/IMPLEMENTATION-PLAN.md`: tick the Phase 7 row in the `## Per-round briefs` section.
5. **After this round is Done, the refactor is complete.** Update `docs/specs/sandbox-runtime/plans/README.md` to mark the whole refactor done, and follow the README's "After all eight rows show Done" cleanup: delete the README, remove the empty `plans/` dir, and move the `## Per-round briefs` section in `IMPLEMENTATION-PLAN.md` into a `## Refactor history` footnote. This final cleanup happens in the same commit if all rounds are Done; otherwise leave it for whichever round is genuinely last.
