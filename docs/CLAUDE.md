# CLAUDE.md — devcontainerctl

The unified `dctl` CLI for AI-agent devcontainer sandboxes, built and run from the user's own configuration in `~/.config/dctl/`.

## Quick Orientation

- `bin/dctl` — thin CLI entrypoint (bootstrap, source modules, dispatch)
- `lib/dctl/` — shell library modules (`common`, `ws`, `image`, `init`, `test`, `auth`, `config`)
- `schemas/` — JSON Schemas for composition manifests and the project registry
- `docs/examples/` — copyable examples in the layout of `~/.config/dctl/` (an image, a manifest, layers); no command reads them and `make install` does not install them
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
- Hook set: `shellcheck`, `shfmt`, `shellharden`, `bashate`, `typos`

## Key Invariants

- `dctl init` registers the project in XDG config under `~/.config/dctl/`, not in a local workspace `.devcontainer/`; the merged `devcontainer.json` is regenerated fresh on every command under `$XDG_RUNTIME_DIR/dctl/devcontainer/<name>/` (never cached)
- Selectable devcontainers are defined by YAML manifests (`*.yaml`) with a `layers` array declaring composition order; the last layer is the leaf, preceding layers are shared; layer directories without manifests are not listed or selectable
- `dctl` resolves `devcontainer.json` through a six-level precedence chain: CLI flag, env var, registry, local file, sibling discovery, user default
- `dctl ws` commands match containers by workspace label, so work-clones keep separate container identity
- `dctl` ships no image, no layer, and no manifest; `make install` installs only `bin/dctl`, `lib/dctl/*.sh`, and the schemas (`~/.local/share/dctl/schemas/`); all runtime operations use user config (`~/.config/dctl/`) exclusively, which the user writes
- `dctl` installs, activates, and names no dev environment manager; each project owns its own dev environment setup, and the user's image carries what the projects need
- Dotfiles are optional and belong in a user layer such as `dotfiles`, not in image build inputs

## Mermaid Diagrams

- Target mermaid **10.2.x** compatibility (nvim markdown-preview renderer)
- Use only `flowchart`, `sequenceDiagram`, `classDiagram`, `stateDiagram-v2`, `erDiagram`, `gantt`, `pie`, `gitgraph`
- Do **not** use `block-beta` (requires 10.9+), `timeline` (requires 10.7+), `mindmap` (requires 10.1+ but buggy), `sankey` (requires 10.3+), or `xychart` (requires 10.5+)
- Avoid special characters in node labels — use `·` instead of `()`, escape parens if needed

## References

- [README.md](../README.md) — product overview, install, CLI, XDG layout
- [QUICKSTART.md](QUICKSTART.md) — shortest setup path
- [ARCHITECTURE.md](ARCHITECTURE.md) — deeper technical rationale and troubleshooting
- [spec/README.md](../spec/README.md) — implemented design/spec set
