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

## Testing

- `make test-unit` — run unit tests
- `make test-integration` — run integration tests
- `make test` — run both unit and integration suites
- `make lint` — run pre-commit lint hooks individually
- `make check` — run the full pre-commit suite

Tests are written with `bats`.

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

- [README.md](../README.md) — product overview, install, CLI, XDG layout
- [QUICKSTART.md](QUICKSTART.md) — shortest setup path
- [ARCHITECTURE.md](ARCHITECTURE.md) — Podman/libkrun architecture overview and runtime model
- [spec/README.md](../spec/README.md) — implemented design/spec set
