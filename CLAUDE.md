# CLAUDE.md — devcontainerctl

Pre-built Podman/libkrun images and the unified `dctl` CLI for AI-agent devcontainer sandboxes.

## Quick Orientation

- `bin/dctl` — dispatcher-only CLI entrypoint
- `lib/dctl/` layout:

| What | Where |
|---|---|
| Internal helpers | `lib/dctl/_lib/<topic>/<name>.sh` |
| Command tree | `lib/dctl/commands/<group>/` |
| Runtime adapter | `lib/dctl/runtime/{common,krun}.sh` |
| Lifecycle interpreter | `lib/dctl/lifecycle.sh` |

- `images/` — managed Containerfiles, one subdir per image
- `devcontainers/` — layer directories plus YAML composition manifests (validated by `schemas/compose.schema.yaml`)
- `systemd/` — weekly image rebuild timer + service
- `tests/` — bats-based unit and integration coverage

## Test Principles (NON-NEGOTIABLE)

1) Idiomatic bats: use bats-assert/bats-support; share fixtures via
   `tests/test_helper.bash`; one logical assertion path per `@test`.
2) Test the public surface — the `dctl <cmd>` CLI and `cmd_*`
   dispatchers — not private helpers (`_foo`, `__bar`).
3) Test behavior and contracts (argv emitted to podman, exit codes,
   stdout/stderr shape, files produced), never internal call sequences
   or private function signatures.
4) Don't test third-party tools (podman, crun, jq, stat, bash builtins).
   Fake them at the boundary with `create_mock` / `record_argv_mock`;
   real binaries only in `*_integration_test.bats` (integration tier)
   or `*_e2e_test.bats` (e2e tier), with skip guards.
5) Deterministic and fast: TEST_TMPDIR fixtures, no real `sleep`,
   no real clocks/network/registries. Filesystem mtime logic must be
   testable without waiting for wall-clock seconds (inject a comparator
   or fake `stat`).
6) Risk-driven coverage: cover ws/init/auth/runtime contracts first;
   don't chase line coverage on trivial string helpers.
7) Clear `@test` names as sentences; minimal mocking; assertions via
   `assert_output` / `assert_success` / `assert_failure` /
   `assert_argv_call`.

## Test Tiers

| Tier          | Scope                                                                                                      | Runs in                |
|---------------|------------------------------------------------------------------------------------------------------------|------------------------|
| `unit`        | TEST_TMPDIR fixtures + faked external CLIs (podman/crun); read-only helpers like `jq`/`yq` allowed. No real wall-clock waits, no real `podman` invocations of the SUT. | pre-commit, `--jobs N` |
| `integration` | Same fixtures and fakes as `unit`, plus tests that exercise real-filesystem mtime / `touch -d` ordering or other behavior that requires sequencing on the real FS clock. | pre-push, `--jobs N`   |
| `e2e`         | Real `podman` + real `krun` + real `/dev/kvm`.                                                             | CI only                |

Tag each file with `# bats file_tags=<tier>`; tag per-test exceptions
with `# bats test_tags=<tier>`.

## Mocking Reference

- `create_mock <name> <exit> [stdout]` — silent mock, fixed stdout.
- `record_argv_mock <name> <exit> [stdout]` — records argv; assert via
  `assert_argv_call` / `assert_argv_contains_sequence`.
- `assert_mock_called <pattern>` / `assert_mock_not_called <pattern>`.
- All defined in `tests/test_helper.bash`.

## Shell Conventions

- Shell scripts use `bash`
- Formatting and linting run through pre-commit
- Hook set: `shellcheck`, `shfmt`, `shellharden`, `bashate`

## Key Invariants

- `dctl init` writes to XDG-managed config/cache under `~/.config/dctl/` and `~/.cache/dctl/`, not to a local workspace `.devcontainer/`
- Selectable devcontainers are defined by YAML manifests (`*.yaml`) with a `layers` array declaring composition order; the last layer is the leaf (user-protected on deploy), preceding layers are shared (reconciled on deploy); layer directories without manifests are not listed or selectable
- `dctl` resolves `devcontainer.json` through a six-level precedence chain: CLI flag, env var, registry, local file, sibling discovery, user default
- `dctl ws` commands match containers by workspace label, so work-clones keep separate container identity
- Installed files (`~/.local/share/dctl/`) are seed sources only — `dctl` never builds, merges, or runs containers from installed files directly; all runtime operations use user config (`~/.config/dctl/`) exclusively
- Installed templates seed user config, but composed devcontainer output is built only from `~/.config/dctl/devcontainer/`
- Dotfiles are optional and belong in a user layer such as `dotfiles`, not in shipped defaults or image build inputs

## Mermaid Diagrams

- Target mermaid **10.2.x** compatibility (nvim markdown-preview renderer)
- Use only `flowchart`, `sequenceDiagram`, `classDiagram`, `stateDiagram-v2`, `erDiagram`, `gantt`, `pie`, `gitgraph`
- Do **not** use `block-beta` (requires 10.9+), `timeline` (requires 10.7+), `mindmap` (requires 10.1+ but buggy), `sankey` (requires 10.3+), or `xychart` (requires 10.5+)
- Avoid special characters in node labels — use `·` instead of `()`, escape parens if needed

## References

- [README.md](README.md) — product overview, install, CLI, XDG layout
- [QUICKSTART.md](docs/QUICKSTART.md) — shortest setup path
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — Podman/libkrun architecture overview and runtime model
- [spec/README.md](spec/README.md) — implemented design/spec set
