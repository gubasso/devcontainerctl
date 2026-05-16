# Phase 20 — Route `dctl ws` + `dctl image` through the runtime adapter (prex task brief)

> Status: Pending
> Companion docs (Codex must read these in stage 1):
> - [docs/specs/sandbox-runtime/SPEC.md](../SPEC.md) (§5.5 adapter interface)
> - [docs/specs/sandbox-runtime/DECISION-LINUX.md](../DECISION-LINUX.md) (single-backend invariant)
> - [docs/specs/sandbox-runtime/IMPLEMENTATION-PLAN.md](../IMPLEMENTATION-PLAN.md) (master overview)
> - `lib/dctl/runtime/common.sh` — the `rt_*` interface from round 10
> - `lib/dctl/runtime/krun.sh` — the only backend
> - `lib/dctl/CLAUDE.md` — post-1.5 layout reference
> Reference: ai-agents-sandbox `:301-302` for default krun resource annotations.
> Depends on: [`15b-command-tree-extraction.md`](15b-command-tree-extraction.md) — must be `Done`. The `commands/<group>/<verb>.sh` layout exists; `lib/dctl/runtime/{common,krun}.sh` and `lib/dctl/lifecycle.sh` exist.
> Output of this round: every container-CLI / devcontainer-CLI shell-out in `dctl ws` and `dctl image` is replaced with `rt_*` calls. Behavior is identical from the user's perspective; the only container CLI invoked anywhere in the codebase is `podman` (via the adapter).

## Task

Replace every `docker` / `devcontainer` shell-out in the `dctl ws` verbs (`commands/ws/*.sh`) and the `dctl image` verbs (`commands/image/*.sh`) with calls into the `rt_*` interface defined in `lib/dctl/runtime/common.sh`. Also rewire `commands/init/_generate_cache.sh` to emit the `runtime: krun` overlay in the cached devcontainer.json (`--runtime krun` in `runArgs` + default krun resource annotations) and to use `rt_image_inspect` for the image-existence check.

This round combines what IMPLEMENTATION-PLAN.md called Phase 2 (`dctl ws`) and Phase 3 (`dctl image`) because they share the same pattern — replace one container-CLI invocation with one `rt_*` call — and together fit comfortably inside a single prex round. The boundary between Phase 2 work and Phase 3 work is preserved in the subsections below so the round's diff stays reviewable.

## Preconditions (must already be true on `develop`)

- Round `15b` is `Done`. `lib/dctl/commands/<group>/<verb>.sh` layout exists for every group. Flat modules are deleted.
- `lib/dctl/runtime/{common,krun}.sh` and `lib/dctl/lifecycle.sh` exist (from round 10).
- `tests/structure_test.bats` is in place and green.
- `dctl test` still prints the round-00 Phase-2 deprecation banner — this round removes the banner once `dctl test` is rewired (see Phase 2 work item 4 below).

## Scope (in this round)

### Phase 2 work — `dctl ws` rewire

1. **Refactor every container-CLI / devcontainer-CLI call in `commands/ws/*.sh`** to use `rt_*`:
   - Every `podman/docker ps -a --filter ...` → `rt_ps`.
   - Every `devcontainer up` / `devcontainer exec` → `rt_run` / `rt_exec`.
   - The bulk-rm path in `commands/ws/down.sh` → `rt_rm`.
2. **Emit the `runtime: krun` overlay in `commands/init/_generate_cache.sh`**: append `--runtime krun` to `runArgs` and the Tier 0 flags (`--cap-drop=ALL`, `--security-opt=no-new-privileges`) — note: round 40 is what configures these in the **leaf** `devcontainer.json`; this round just ensures the **cache** is wired to honor them. Default krun resource annotations: `--annotation krun.ram_mib=4096 --annotation krun.cpus=2` (matches ai-agents-sandbox `:301-302`). Make overridable via the `runtime.resources` block — but the schema for that block does not land until round 70 (Phase 7), so for this round hardcode the defaults and leave a `TODO(70)` marker.
3. **Update the image-existence check** in `commands/init/_generate_cache.sh`: the container-CLI `image inspect` → `rt_image_inspect`.
4. **Remove the round-00 Phase-2 deprecation banner from `commands/test/run.sh`** — now that `dctl ws` is podman-only, `dctl test` will work as expected once its own shell-outs are rewired. **However**, `dctl test` itself currently uses `devcontainer up`/`exec` at the test level in `commands/test/run.sh`. Choose one of:
   - **(a) Rewire `commands/test/run.sh`** to call `rt_run`/`rt_exec` like the `ws` verbs do, removing the banner. This is the clean option.
   - **(b) Leave `dctl test` calling `devcontainer` and keep the banner** for one more round (round 60 — test-suite refactor — naturally rewires it via the mock-target updates).
   Stage 1 planning picks (a) or (b) based on how much work `commands/test/run.sh` requires; default to (a) unless it materially expands the round.
5. **Preserve worktree mount logic.** `_lib/workspace/git_worktree.sh` (the shared `.git` mount) is runtime-agnostic and travels through `rt_run`'s extra-args. Verify it still works under the new path; no edits expected.
6. **Preserve label-based container identity.** `_lib/workspace/label_filter.sh` is reused unchanged — Podman honors `--filter label=...` identically. **Verify before assuming**: if Podman's label-filter semantics differ for `--filter label=K=V` vs `--filter label=K=` (key-only) in a way the `dctl` codebase exercises, patch the helper. The smoke from round 10 already verified the common case.
7. **Pin the network backend** if the round-10 smoke surfaced a preference (e.g. `--network slirp4netns` or `--network pasta`). This is a one-line `rt_run` flag. If undecided, leave it unpinned and document in `DECISION-LINUX.md`.

### Phase 3 work — `dctl image` rewire

1. **Refactor every container-CLI / build-CLI call in `commands/image/*.sh`** to use `rt_*`:
   - `commands/image/build.sh` legacy build-tool preflight → `podman info` check inside `rt_build`'s preflight (the round-10 `rt_build` already memoizes the doctor preflight; this is just removing the legacy probe).
   - `commands/image/build.sh` legacy build invocation → `podman build` via `rt_build`.
   - `commands/image/list.sh` image-list query → `podman images` directly (no new `rt_*` function needed — image listing is a simple wrapper).
2. **Podman build secrets:** the build passes `gh_token` as a secret to avoid npm rate limits during `mise install`. Use `podman build --secret id=gh_token,src=<path>`. Containerfile `RUN --mount=type=secret,id=gh_token ...` lines are OCI-frontend-compatible and work under Podman/Buildah unchanged. No Containerfile edits required.
3. **Preserve `images/agents/Containerfile` openSUSE Tumbleweed base.** Already migrated per commit `80071af`. Do not pre-emptively change. Touch only if `podman build` surfaces a syntax issue.
4. **`make install-systemd`** keeps working unchanged — the weekly rebuild service invokes `dctl image build --all`, which is runtime-agnostic.

## Out of scope for this round (DO NOT touch)

- Tier 0 hygiene flags **in the leaf devcontainer.json** (`--cap-drop=ALL`, `--security-opt=no-new-privileges`, tmpfs) — round 40's job. This round only wires `_generate_cache.sh` to honor whatever is in `runArgs`.
- The egress allowlist (`commands/net/*`) — round 40's job.
- Dockerfile → Containerfile rename — round 70's job. This round still references `Dockerfile` in path-builder helpers (`_lib/paths.sh`) and existence checks.
- The full `runtime.resources` manifest-schema extension — round 70's job. Hardcode the defaults here.
- Test-suite refactor (rewriting `tests/dctl_test.bats` mocks) — round 60's job. If `dctl test` is rewired here (option a above), only the `commands/test/run.sh` source changes; the bats test file is untouched.

## Implementation guidance

### Network backend pinning

Round 10's smoke recorded the host's active backend. If Phase 0/10 settled on a specific backend (pasta vs slirp4netns), pin it here via `--network <backend>` in `rt_run`. If not, leave unpinned and append a one-paragraph entry to `DECISION-LINUX.md` documenting the decision deferral to a future round.

### Label-filter compatibility check

Add a small bats unit test (in `tests/dctl_test.bats` or a new `tests/runtime_krun_test.bats` stub — round 60 will expand it) that asserts `rt_ps` returns the expected container after `rt_run`, against a real (or mocked) Podman invocation. Skip-gracefully if Podman is missing.

### Default krun resource annotations

`--annotation krun.ram_mib=4096 --annotation krun.cpus=2` should be emitted by `rt_run` in `lib/dctl/runtime/krun.sh`, **not** baked into `_generate_cache.sh`. Put it in `rt_run` so a future per-manifest override (round 70) only needs to read the manifest's `runtime.resources` block and pass the values in.

### Re-anchor sanity check

Round 15b should have removed every pre-reorg `file:line` reference in this brief. If you encounter a stale anchor, re-anchor it in place during this round's edits and leave a one-line note in the commit message — stage-4 review uses that to flag round-15b incompleteness.

## Acceptance gates (all must pass before stage 4 review approves)

- `make check` passes (lint + bats + format).
- `grep -rn 'docker\|devcontainer up\|devcontainer exec' lib/dctl/commands/ws/ lib/dctl/commands/image/ lib/dctl/commands/init/` returns zero hits (no surviving non-`rt_*` container-CLI shell-outs in the rewired groups).
- `dctl ws up` against a real workspace on the developer's host succeeds; `podman inspect <ctr> --format '{{.OCIRuntime}}'` returns `krun`.
- `dctl ws exec -- echo ok` returns `ok` with `-it` semantics preserved.
- `dctl ws down` cleanly removes the container; `rt_ps` shows zero matches afterward.
- `dctl image build <name>` against a known image builds successfully via `podman build`; the built image shows up in `podman images`.
- `dctl image list` lists images via `podman images`.
- `dctl init` regenerates the cached `devcontainer.json` with `--runtime krun`, `--annotation krun.ram_mib=4096`, `--annotation krun.cpus=2` in `runArgs`.
- If option (a) was chosen: `dctl test` no longer prints the round-00 banner, and its internal `devcontainer up/exec` calls are rewired to `rt_run`/`rt_exec`.
- Two work-clones of the same repo continue to produce two distinct containers (label-based identity is preserved — verify with `rt_ps` against both).

## Risks & known gotchas

- **Label-filter semantics divergence.** Podman vs Docker `--filter label=` is identical in the common case but can diverge for empty-value filters. Verify the `dctl` codebase's exact filter shape against `man 1 podman-ps` before declaring done.
- **Default krun resource annotations may surprise users.** A user who previously got "whatever the host allocated" now gets 4 GiB RAM + 2 CPUs explicitly. Document this in the round's commit message and in `DECISION-LINUX.md` if not already there.
- **The `dctl test` rewire (option a) doubles this round's scope.** If the implementation budget tightens, default to option (b) — leave `dctl test` for round 60.
- **`_generate_cache.sh` emits the runtime overlay but does not enforce Tier 0 flags.** Round 40 adds those to the leaf `devcontainer.json`. Until round 40 ships, `rt_run` will pass `runArgs` that lack `--cap-drop=ALL` — that's expected.
- **libkrun #674** vsock workaround already lives in `rt_run` (round 10). Don't duplicate.

## Plan-file cleanup (Codex must perform in stage 3, as part of the implementation commit)

1. Delete this file: `docs/specs/sandbox-runtime/plans/20-ws-and-image-adapter-rewire.md`.
2. Update `docs/specs/sandbox-runtime/plans/README.md`: this round's row `Status` → `Done — <commit-sha> — <date>`.
3. Promote durable content:
   - If a network-backend decision was made (pasta vs slirp4netns), append it to `docs/specs/sandbox-runtime/DECISION-LINUX.md`.
   - The default krun resource annotation rationale (4 GiB / 2 CPUs) lives in `lib/dctl/runtime/krun.sh` source comments.
4. Update `docs/specs/sandbox-runtime/IMPLEMENTATION-PLAN.md`: tick the Phase 2 + Phase 3 rows in the `## Per-round briefs` section.
