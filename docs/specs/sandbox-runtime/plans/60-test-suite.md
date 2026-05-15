# Phase 60 — Test suite refactor + adapter/auth/net coverage (prex task brief)

> Status: Pending
> Companion docs (Codex must read these in stage 1):
> - [docs/specs/sandbox-runtime/SPEC.md](../SPEC.md) (§4.1, §5.1, §7 — Tier 0 acceptance)
> - [docs/specs/sandbox-runtime/IMPLEMENTATION-PLAN.md](../IMPLEMENTATION-PLAN.md) (master overview)
> - `lib/dctl/runtime/{common,krun}.sh` — the adapter shape under test
> - `lib/dctl/_lib/auth/*` and `lib/dctl/commands/net/*` — the surfaces under test
> Depends on: [`40-tier0-hygiene-and-egress.md`](40-tier0-hygiene-and-egress.md) — must be `Done`. Tier 0 hygiene is on the default path; the egress allowlist exists; ephemeral-creds helper exists.
> Output of this round: every behavior change introduced in rounds 00–40 is covered by a bats test; the existing suite passes against the new runtime; an integration smoke gate runs against a KVM host.

## Task

Refactor `tests/dctl_test.bats` (1,749 LOC — biggest test file) so its hardcoded container-CLI / build-CLI invocations call into the adapter instead, and add three new bats files covering the round-10/15a/15b/40 deliverables that are not currently asserted anywhere. Add an integration smoke target (KVM-required, tagged `integration`) and ensure `make test` / `make check` pass.

This is a **test-only** round. No source code changes outside `tests/`.

## Preconditions (must already be true on `develop`)

- Round `40` is `Done`. Tier 0 hygiene + egress allowlist + ephemeral creds are on the default path.
- `tests/structure_test.bats` (from round 15b) is in place and green.
- `make check` is green on `develop`.

## Scope (in this round)

### Edit: `tests/dctl_test.bats` (1,749 LOC)

1. **Replace hardcoded container-CLI / build-CLI invocations with `rt_*`** — every `docker ps`, `docker rm`, `docker build`, `docker info` mock target becomes an `rt_ps`/`rt_rm`/`rt_build` mock. Behavior-level assertions are unchanged.
2. **Add unit coverage for `lib/dctl/runtime/krun.sh`:**
   - Preflight branches: missing `/dev/kvm`, missing crun-krun (`+LIBKRUN` absent from `crun --version`), libkrun too old (below `MIN_LIBKRUN_VER`).
   - Command construction: assert on the emitted arg vector for `rt_run`, `rt_exec`, `rt_build`, `rt_ps`, `rt_rm`, `rt_image_inspect`. No real podman invocation — mock the podman binary via `PATH` shim or bats-mock.
3. **Update `source` paths** to the post-15a/15b layout (round 15b's re-anchor pass should have left no stale paths, but verify).

### New: `tests/runtime_krun_test.bats`

- Adapter contract tests (mock-based). One test per `rt_*` function asserting:
  - The emitted command line (podman flags, runtime, label, env, secrets).
  - Error handling on preflight failure (each doctor-probe branch).
  - Memoization of the doctor preflight (called once per session).
- libkrun #674 workaround assertion: if the workaround flag is on, `rt_run` includes the relevant env or sysctl.

### New: `tests/auth_token_forwarding_test.bats`

- Assert **no host config dir** appears in `rt_run` mount args (`~/.config/gh`, `~/.claude`, `~/.codex`, `~/.gemini` must be absent).
- Assert `GH_TOKEN` and `GITLAB_TOKEN` are emitted as `--env` flags when the host has the respective CLIs configured.
- Assert ephemeral-creds tmpdir is created under `$DCTL_CACHE_DIR/sessions/<workspace-hash>/` on `rt_run`.
- Assert ephemeral-creds tmpdir is **removed** on `dctl ws down`.
- Mock the on-host credential files via `mktemp -d` fixtures.

### New: `tests/net_allowlist_test.bats`

- `net_compose_allowlist()` returns the expected union of defaults + user list, including git-remote auto-extraction.
- `dctl net allow foo.example` appends to the leaf `devcontainer.json` and the cache is regenerated.
- `dctl net show` prints the effective list with origin annotations (`default` vs `user`).
- Mock `git remote -v` output via a fixture workspace.

### New: `tests/test_helper.bash` updates

- Add helpers for mocking the podman binary, `crun --version`, `ldconfig -p`, `getfacl /dev/kvm` outputs.
- Add a helper to spin up a tmpdir fixture for the `$DCTL_CACHE_DIR/sessions/` path.

### New: `bats tests/ --filter-tags integration` smoke

- One scenario tagged `integration`: `dctl ws up` against the `general` manifest on a KVM-capable openSUSE Tumbleweed host. Assert `podman inspect` shows `OCIRuntime: krun`, exec a command, tear down.
- **Skip** the integration tag in CI without KVM (the bats `setup_file` checks `[ -e /dev/kvm ] && [ -r /dev/kvm ]`). gVisor fallback is out of scope for this plan.
- Add a `make test-integration` target if one doesn't exist; otherwise reuse.

### If round 20 chose option (b)

`commands/test/run.sh` still uses `devcontainer up`/`exec`. This round rewires it as part of the `tests/dctl_test.bats` refactor — replace those calls with `rt_run`/`rt_exec` and drop the round-00 deprecation banner. If round 20 chose option (a), this is already done.

## Out of scope for this round (DO NOT touch)

- Source code outside `tests/` and (if option-b above) `commands/test/run.sh`.
- Dockerfile → Containerfile rename in test fixtures (`touch ".../Dockerfile"` setup) — round 70's job. This round still tests against `Dockerfile`.
- Schema additions (`runtime.resources`, `network.allow`) — round 70.

## Implementation guidance

### Mocking podman

Use a `PATH` shim approach: `tests/test_helper.bash` sets up a `$BATS_TEST_TMPDIR/bin/podman` script that records its argv to a file and exits 0. Each test asserts on the recorded argv. This is simpler and more debuggable than `bats-mock`.

```bash
setup() {
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  cat > "$BATS_TEST_TMPDIR/bin/podman" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$BATS_TEST_TMPDIR/podman.argv"
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/podman"
}
```

### Mocking the doctor preflight

The runtime adapter memoizes the doctor preflight. Tests that want to skip preflight set `_DCTL_KRUN_PREFLIGHT_OK=1` before invoking `rt_*`. Tests that want to assert preflight failure unset it and stub `crun --version` etc. via the PATH shim.

### Integration test gating

```bash
setup_file() {
  if [ ! -r /dev/kvm ]; then
    skip "Integration tests require /dev/kvm (KVM-capable host)"
  fi
  if ! command -v podman >/dev/null; then
    skip "Integration tests require podman"
  fi
}
```

Tag the file with `# bats file_tags=integration` at the top.

### Behavior-level assertions

Do not change the **semantics** of any existing test. Round 60 only redirects mocked targets and adds new tests; it does not weaken or strengthen existing assertions. If a behavior-level test fails after the source-side rewires from rounds 20/40, that's a bug in the rewire — flag in stage-4 review.

## Acceptance gates (all must pass before stage 4 review approves)

- `make check` passes (lint + bats + format).
- `make test-integration` (or equivalent) passes on the developer's KVM host.
- `bats tests/` (full suite, non-integration) passes everywhere including CI.
- Three new test files exist and contain at least the assertions enumerated above:
  - `tests/runtime_krun_test.bats`
  - `tests/auth_token_forwarding_test.bats`
  - `tests/net_allowlist_test.bats`
- `tests/dctl_test.bats` no longer contains direct `docker` / `devcontainer up` / `devcontainer exec` invocations; mocks route through `rt_*`.
- `tests/test_helper.bash` exports the podman PATH-shim helper and the credential-fixture helper.
- If option-b path: `commands/test/run.sh` no longer prints the round-00 deprecation banner, and its `devcontainer up/exec` calls are rewired to `rt_run`/`rt_exec`.

## Risks & known gotchas

- **`tests/dctl_test.bats` is 1,749 LOC.** Refactoring at scale risks subtle behavior changes if a mock target is renamed without updating every test that depends on it. Run the full suite after each block of edits, not at the end.
- **PATH shim ordering.** Some bats tests already manipulate `PATH`. Ensure the shim runs before any test-local PATH manipulation, otherwise the mock isn't picked up.
- **`make test-integration` may not exist.** Phase 6 in IMPLEMENTATION-PLAN.md added it; verify against `Makefile`. If absent, add a target that runs `bats tests/ --filter-tags integration`.
- **Long-running integration smoke.** The full `dctl ws up` on a fresh workspace can take minutes (image pull + container start + lifecycle hooks). Mark it explicitly slow if bats supports tagging by duration.
- **Mock vs real podman boundary.** Unit tests use the PATH shim. The integration smoke uses real podman. Do not mix; the integration smoke should not rely on the mock.

## Plan-file cleanup (Codex must perform in stage 3, as part of the implementation commit)

1. Delete this file: `docs/specs/sandbox-runtime/plans/60-test-suite.md`.
2. Update `docs/specs/sandbox-runtime/plans/README.md`: this round's row `Status` → `Done — <commit-sha> — <date>`.
3. Promote durable content:
   - The mock conventions (`PATH` shim shape, preflight skip flag) are documented in `tests/test_helper.bash` source comments.
   - Nothing else from this round needs promotion — the tests themselves are the documentation.
4. Update `docs/specs/sandbox-runtime/IMPLEMENTATION-PLAN.md`: tick the Phase 6 row in the `## Per-round briefs` section.
