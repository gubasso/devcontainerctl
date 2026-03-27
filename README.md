# devcontainerctl

Pre-built Docker images and a unified `dctl` CLI for devcontainer workspaces — especially useful for running AI coding agents (Claude Code, Codex, OpenCode, Gemini CLI) in safe, isolated sandboxes.

- One-command project setup with `dctl init` and reusable templates.
- Pre-built images with AI agent tooling and language-specific layers ready to go.
- A composable config system built around `_base`, per-template deltas, and user-editable XDG config.
- Multi-agent workflows with shared containers, token forwarding, and work-clone support.

## What You Get

### Ready-to-use images

| Image | What it includes |
| --- | --- |
| `devimg/agents:latest` | Shared foundation with dev tools, Bun, Node LTS via mise, Rust tooling, gh, glab, neovim, Claude Code, Codex, OpenCode, and Gemini CLI |
| `devimg/python-dev:latest` | `agents` plus Poetry-oriented Python project support |
| `devimg/rust-dev:latest` | `agents` plus rustup with project-pinned toolchain flow |
| `devimg/zig-dev:latest` | `agents` plus anyzig, minisign, and `zig-zls-init` |

### Ready-to-use templates

`_base` is the shared internal foundation. The selectable templates below add the user-facing project shape on top of it.

| Template | Image | What it adds |
| --- | --- | --- |
| `general` | `devimg/agents:latest` | Minimal general-purpose sandbox with pre-commit bootstrap |
| `coordinator` | `devimg/agents:latest` | Coordinator workflow with a read-only parent-area mount for sibling repo visibility |
| `python` | `devimg/python-dev:latest` | Poetry cache volume and Python bootstrap via `bash -ic dev-py` |
| `rust` | `devimg/rust-dev:latest` | Rust cache volumes and `cargo build` bootstrap |
| `zig` | `devimg/zig-dev:latest` | Zig/ZLS cache volumes and `zig-zls-init` bootstrap |

### Composable config

```text
_base + template  ──dctl init──>  ~/.config/dctl/  ──merge──>  ~/.cache/dctl/  ──dctl ws up──>  container
```

Installed templates are seeded into user-editable config under `~/.config/dctl/devcontainer/`. `dctl init` merges `_base` and the selected template into a cached `devcontainer.json` under `~/.cache/dctl/devcontainer/`, and `dctl ws up` consumes that merged file.

## Quick Start

Prerequisites:

- Docker with `buildx`
- Dev Container CLI (`devcontainer`)
- Dotfiles repo at `~/.dotfiles` or `DOTFILES=/path/to/dotfiles`

```bash
make install
dctl image build --all
cd ~/projects/my-api
dctl init --template python
dctl ws up
dctl ws shell
```

That flow installs `dctl`, builds the managed images, deploys the Python template into XDG config/cache, starts the container for the current workspace, and drops you into a shell inside it.

## Workflow Comparison

| Task | `dctl` | Dev Container CLI | Docker |
| --- | --- | --- | --- |
| Set up a new Python workspace | `dctl init --template python` | Create `.devcontainer/devcontainer.json` manually | Write a `Dockerfile` and container run args manually |
| Start the workspace | `dctl ws up` | `devcontainer up --workspace-folder . --config /path/to/devcontainer.json` | `docker run -it ...` |
| Open a shell | `dctl ws shell` | `devcontainer exec --workspace-folder . bash` | `docker exec -it <container> bash` |
| Run an agent | `dctl ws shell claude` | `devcontainer exec --workspace-folder . bash -lic claude` | `docker exec -it <container> bash -lic claude` |
| Run a command | `dctl ws exec -- pytest` | `devcontainer exec --workspace-folder . pytest` | `docker exec -it <container> pytest` |
| Rebuild after config/image changes | `dctl ws reup` | `devcontainer up --workspace-folder . --remove-existing-container` | Rebuild image, remove container, rerun container |
| Build managed base images | `dctl image build --all` | No built-in global image build flow | Rebuild every project image separately |
| Stop and remove the workspace | `dctl ws down` | `devcontainer stop` + manual `docker rm` | `docker stop <container> && docker rm <container>` |

## Config System

`_base` owns the shared infrastructure:

- `remoteUser` and UID behavior
- dotfiles mount and dotfiles bootstrap hook
- shared auth/config mounts for tools such as `gh`, `glab`, Claude Code, Codex, OpenCode, Gemini, and editor config
- base container env for terminal integration

Templates add the project-specific layer:

- the image tag
- language-specific cache volumes
- language-specific `postCreateCommand` entries

Your source of truth lives under `~/.config/dctl/devcontainer/`. `dctl init` seeds `_base` plus the selected template there, and the merged output in `~/.cache/dctl/devcontainer/<name>/devcontainer.json` is what `dctl ws up` actually uses.

### Config resolution

`dctl` resolves `devcontainer.json` in this order:

1. `--config` CLI flag
2. `DCTL_CONFIG` environment variable
3. Per-project registry in `~/.config/dctl/projects.yaml`
4. Local `.devcontainer/devcontainer.json`
5. Work-clone sibling discovery
6. User global default at `~/.config/dctl/default/devcontainer.json`

### Work-clone workflow

If you work in sibling clones such as `repo/` and `repo.42-add-auth/`, `dctl` can resolve the main repo's config for the work-clone while still keeping the container identity keyed to the current workspace path. That means each clone gets its own container, even when they share config.

### Editing config and applying changes

```bash
$EDITOR ~/.config/dctl/devcontainer/python/devcontainer.json
dctl init
dctl ws reup
```

Edit the config-layer file, rerun `dctl init` to regenerate the cached merged config if needed, then use `dctl ws reup` to recreate the container from that updated cache.

## CLI Reference

### Global options

```bash
dctl --config /path/to/devcontainer.json <command-group> [command]
dctl help
dctl version
```

`--config` overrides config resolution for commands that need a `devcontainer.json`.

### `dctl init`

```bash
dctl init --template python
dctl init --list
dctl init --force --template rust
dctl init --no-register --template zig
```

- `--template <name>` selects a template explicitly
- `--list` prints the selectable templates
- `--force` re-seeds config from installed templates and regenerates cache
- `--no-register` skips writing the project registry entry

### `dctl ws`

```bash
dctl ws up
dctl ws reup
dctl ws shell
dctl ws shell claude
dctl ws exec -- pytest
dctl ws run -- "pytest -q"
dctl ws status
dctl ws down
```

`dctl ws` adds a few important host-side conveniences:

- forwards `GH_TOKEN` and `GITLAB_TOKEN` into the container by extracting them from `gh`/`glab` when available
- forwards terminal-related env vars such as `TERM`, `COLORTERM`, `TERM_PROGRAM`, and Kitty-specific vars
- bind-mounts the shared git common dir automatically for linked worktrees

### `dctl image`

```bash
dctl image build
dctl image build agents
dctl image build --all
dctl image build --refresh-agents agents
dctl image build --full-rebuild
dctl image build --dry-run
dctl image list
```

`dctl image build` resolves Dockerfiles through a two-layer hierarchy:

1. `~/.config/dctl/images/<target>/Dockerfile`
2. `~/.local/share/dctl/images/<target>/Dockerfile`

### `dctl config`

```bash
dctl config
```

Only `help` is implemented today. The project registry lives at `~/.config/dctl/projects.yaml`.

### `dctl test`

```bash
dctl test
```

Runs the workspace smoke test: prerequisite checks, managed image build if needed, `devcontainer up`, `devcontainer exec`, and cleanup.

## Image Architecture

```text
Debian bookworm-slim
        │
        ▼
devimg/agents:latest
  shared tools, agent CLIs, runtime managers, shell/dev tooling
        │
        ├── devimg/python-dev:latest
        ├── devimg/rust-dev:latest
        └── devimg/zig-dev:latest
```

`agents` is the shared base. The language-specific images add only the runtime-specific tooling and cache strategy needed for that ecosystem.

## XDG Layout

| Directory | Purpose |
| --- | --- |
| `~/.local/share/dctl/` | Installed assets: images, templates, schemas |
| `~/.config/dctl/` | User config: deployed devcontainer config, registry, image overrides, defaults |
| `~/.cache/dctl/` | Generated artifacts: merged `devcontainer.json` cache |

All of these honor `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, and `XDG_CACHE_HOME`.

## Automation

For weekly managed-image rebuilds, install the user units and enable the timer:

```bash
make install-systemd
systemctl --user daemon-reload
systemctl --user enable --now dctl-image-build.timer
```

The timer runs `dctl image build --all` on a weekly schedule.

## Install / Uninstall

### Install

```bash
make install
```

This installs:

- `dctl` to `~/.local/bin/dctl`
- shell modules to `~/.local/lib/dctl/`
- managed Dockerfiles to `~/.local/share/dctl/images/`
- templates to `~/.local/share/dctl/templates/`
- schema files to `~/.local/share/dctl/schemas/`

`make install` does not write to `~/.config/dctl/` or `~/.cache/dctl/`.

### Install systemd units

```bash
make install-systemd
```

This installs `dctl-image-build.service` and `dctl-image-build.timer` into the user systemd directory.

### Uninstall

```bash
make uninstall
make uninstall-systemd
```

Use `make uninstall` to remove the installed binary, shell modules, templates, Dockerfiles, and schemas. Use `make uninstall-systemd` to remove and disable the weekly rebuild timer.

## Further Reading

- [QUICKSTART.md](docs/QUICKSTART.md) for a short setup path
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) for deeper technical rationale and troubleshooting
- [spec/README.md](spec/README.md) for the implemented design/spec set
