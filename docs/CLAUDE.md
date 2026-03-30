# CLAUDE.md — devcontainerctl

Pre-built Docker images and the unified `dctl` CLI for AI-agent devcontainer sandboxes.

## Quick Orientation

- `bin/dctl` — thin CLI entrypoint (bootstrap, source modules, dispatch)
- `lib/dctl/` — shell library modules (`common`, `ws`, `image`, `init`, `test`, `auth`, `config`)
- `images/` — managed Dockerfiles, one subdir per image
- `devcontainers/` — `_00-base` plus selectable `devcontainer.json` templates
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

- `dctl init` writes to XDG-managed config/cache under `~/.config/dctl/` and `~/.cache/dctl/`, not to a local workspace `.devcontainer/`
- `_00-base` is internal and excluded from template discovery and `dctl init --list`
- `dctl` resolves `devcontainer.json` through a six-level precedence chain: CLI flag, env var, registry, local file, sibling discovery, user default
- `dctl ws` commands match containers by workspace label, so work-clones keep separate container identity
- `dctl image build` prefers user Dockerfile overrides in `~/.config/dctl/images/` over installed Dockerfiles in `~/.local/share/dctl/images/`
- Installed templates seed user config, but composed devcontainer output is built only from `~/.config/dctl/devcontainer/`
- Dotfiles are optional and belong in a user layer such as `_01-dotfiles`, not in shipped defaults or image build inputs

## References

- [README.md](../README.md) — product overview, install, CLI, XDG layout
- [QUICKSTART.md](QUICKSTART.md) — shortest setup path
- [ARCHITECTURE.md](ARCHITECTURE.md) — deeper technical rationale and troubleshooting
- [spec/README.md](../spec/README.md) — implemented design/spec set
