# devcontainerctl

Pre-built Docker images and a unified `dctl` CLI for devcontainer workspaces — especially useful for running AI coding agents (Claude Code, Codex, OpenCode, Gemini CLI) in safe, isolated sandboxes.

- One-command project setup with `dctl init` and reusable templates.
- Pre-built images with AI agent tooling and language-specific layers ready to go.
- A composable config system built around `_00-base`, optional `_NN-*` user layers, and user-editable XDG config.
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

`_00-base` is the shared internal foundation. The selectable templates below add the user-facing project shape on top of it.

| Template | Image | What it adds |
| --- | --- | --- |
| `general` | `devimg/agents:latest` | Minimal general-purpose sandbox with pre-commit bootstrap |
| `coordinator` | `devimg/agents:latest` | Coordinator workflow with a read-only parent-area mount for sibling repo visibility |
| `python` | `devimg/python-dev:latest` | Poetry cache volume and pre-commit bootstrap |
| `rust` | `devimg/rust-dev:latest` | Rust cache volumes and `cargo build` bootstrap |
| `zig` | `devimg/zig-dev:latest` | Zig/ZLS cache volumes and `zig-zls-init` bootstrap |

### How `dctl init --template` works

Each template bundles two things: a `devcontainer.json` config and a managed Dockerfile (the image that config references). When you run `dctl init --template python`, `dctl` seeds **both** into your user config:

```text
Installed (seed sources only, never used at runtime)
  ~/.local/share/dctl/devcontainers/python/devcontainer.json
  ~/.local/share/dctl/images/python-dev/Dockerfile

        ──dctl init──>

User config (runtime source of truth, user-editable)
  ~/.config/dctl/devcontainer/_00-base/devcontainer.json   ← shared base layer
  ~/.config/dctl/devcontainer/python/devcontainer.json     ← template layer
  ~/.config/dctl/images/python-dev/Dockerfile              ← managed Dockerfile

        ──merge──>

Cache (generated, not edited)
  ~/.cache/dctl/devcontainer/python/devcontainer.json      ← merged output used by dctl ws up
```

After init, all runtime operations (`dctl image build`, `dctl ws up`, `dctl test`) use only the user config and cache — never the installed files directly. You can freely edit the user config files to customize your setup.

### Composable config

The devcontainer config uses a layered merge system:

- `_00-base` owns the shared universal infrastructure (remote user, auth mounts, terminal env)
- Optional `_NN-*` user layers add personal config (dotfiles, editor mounts)
- The selected template adds the project-specific layer (image tag, cache volumes, bootstrap commands)

`dctl init` merges all `_*/devcontainer.json` layers alphabetically, then merges the selected template on top. The merge output is cached under `~/.cache/dctl/devcontainer/` and consumed by `dctl ws up`.

## Quick Start

Prerequisites:

- Docker with `buildx`
- Dev Container CLI (`devcontainer`)

```bash
make install
cd ~/projects/my-api
dctl init --template python
dctl image build
dctl ws up
dctl ws shell
```

1. `make install` — installs `dctl` and copies images/templates to `~/.local/share/dctl/` (seed sources only)
2. `dctl init --template python` — seeds the Python `devcontainer.json` layers and `python-dev` Dockerfile into `~/.config/dctl/`, merges config to `~/.cache/dctl/`, and registers the project
3. `dctl image build` — builds `devimg/python-dev:latest` from the seeded Dockerfile in `~/.config/dctl/images/python-dev/`
4. `dctl ws up` — starts the devcontainer using the merged config from `~/.cache/dctl/`
5. `dctl ws shell` — drops you into a shell inside the running container

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

`_00-base` owns the shared universal infrastructure:

- `remoteUser` and UID behavior
- readonly `.gitconfig`
- shared auth/config mounts for `gh`, `glab-cli`, and Claude
- base container env for `TERM` and `COLORTERM`

Templates add the project-specific layer:

- the image tag
- language-specific cache volumes
- language-specific `postCreateCommand` entries

`dctl init` discovers every `~/.config/dctl/devcontainer/_*/devcontainer.json`, merges those internal layers alphabetically, then merges the selected template on top. Installed templates under `~/.local/share/dctl/devcontainers/` are only used to seed missing user config files.

### Custom layers

Personal configuration is now opt-in. To add dotfiles, editor mounts, or extra terminal integration, copy [examples/_01-dotfiles/devcontainer.json](/workspaces/devcontainerctl/examples/_01-dotfiles/devcontainer.json) into `~/.config/dctl/devcontainer/_01-dotfiles/devcontainer.json` and edit it for your host paths.

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

Edit the user config layer file, rerun `dctl init` to regenerate the cached merged config if needed, then use `dctl ws reup` to recreate the container from that updated cache.

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
dctl init --image-only --template python
dctl init --devcontainer-only --template python
dctl init --list
dctl init --force --template rust
dctl init --reset --template rust
dctl init --no-register --template zig
```

- `--template <name>` selects a template and seeds both its `devcontainer.json` layers and the associated managed Dockerfile into user config (`~/.config/dctl/`)
- `--image-only` seeds only the managed Dockerfile (skip devcontainer deploy and smoke test)
- `--devcontainer-only` seeds only the devcontainer config layers (skip Dockerfile seeding)
- `--list` prints the selectable templates
- `--force` rebuilds the cached merged config and re-registers (preserves your user config)
- `--reset` re-seeds config from installed defaults, rebuilds cache, and re-registers (overwrites user config)
- `--no-register` skips writing the project registry entry

On first-time init (or with `--force`/`--reset`), `dctl init` seeds both the devcontainer config layers and the template's managed Dockerfile to user config. Already-registered projects skip seeding unless forced. After seeding, all runtime operations (`dctl image build`, `dctl ws up`) use user config exclusively — installed files are never used directly.

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

`dctl image build` resolves Dockerfiles from user config only:

- `~/.config/dctl/images/<target>/Dockerfile`

Run `dctl init` to seed image configs from installed defaults.

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

| Directory | Purpose | Used at runtime? |
| --- | --- | --- |
| `~/.local/share/dctl/` | Installed assets: Dockerfiles, devcontainer templates, schemas. Seed sources only. | No — only read by `dctl init` to populate user config |
| `~/.config/dctl/` | User config: seeded devcontainer layers, seeded Dockerfiles, project registry, defaults | Yes — sole runtime source for builds, merges, and container operations |
| `~/.cache/dctl/` | Generated artifacts: merged `devcontainer.json` output | Yes — consumed by `dctl ws up` |

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
- managed Dockerfiles to `~/.local/share/dctl/images/` (seed sources — not used at runtime)
- devcontainer templates to `~/.local/share/dctl/devcontainers/` (seed sources — not used at runtime)
- schema files to `~/.local/share/dctl/schemas/`

`make install` does not write to `~/.config/dctl/` or `~/.cache/dctl/`. Run `dctl init --template <name>` after install to seed images and config into user config for runtime use.

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
