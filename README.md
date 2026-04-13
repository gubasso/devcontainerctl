# devcontainerctl

Pre-built Docker images and a unified `dctl` CLI for devcontainer workspaces — especially useful for running AI coding agents (Claude Code, Codex, OpenCode, Gemini CLI) in safe, isolated sandboxes.

- A two-step project setup flow with `dctl deploy` and `dctl init`.
- Pre-built images with AI agent tooling and language-specific layers ready to go.
- A composable config system built around manifest-backed layer stacks and user-editable XDG config.
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

`base` is the shared shipped foundation layer. Selectable configs declare their full composition order in YAML manifests.

| Template | Image | What it adds |
| --- | --- | --- |
| `general` | `devimg/agents:latest` | Minimal general-purpose sandbox with pre-commit bootstrap |
| `coordinator` | `devimg/agents:latest` | Coordinator workflow with a read-only parent-area mount for sibling repo visibility |
| `python` | `devimg/python-dev:latest` | Poetry cache volume and pre-commit bootstrap |
| `rust` | `devimg/rust-dev:latest` | Rust cache volumes and `cargo build` bootstrap |
| `zig` | `devimg/zig-dev:latest` | Zig/ZLS cache volumes and `zig-zls-init` bootstrap |

### How `dctl deploy` + `dctl init` work

`dctl deploy` copies installed seed assets into user config. `dctl init` then
selects only from that deployed config, builds any missing managed image, and
registers the current project:

```text
Installed (seed sources only, never used at runtime)
  ~/.local/share/dctl/devcontainers/python.yaml             ← manifest for the python config
  ~/.local/share/dctl/devcontainers/base/devcontainer.json  ← shared base layer
  ~/.local/share/dctl/devcontainers/python/devcontainer.json
  ~/.local/share/dctl/images/python-dev/Dockerfile

        ──dctl deploy──>

User config (runtime source of truth, user-editable)
  ~/.config/dctl/devcontainer/python.yaml                  ← deployed manifest
  ~/.config/dctl/devcontainer/base/devcontainer.json       ← shared base layer
  ~/.config/dctl/devcontainer/python/devcontainer.json     ← leaf layer
  ~/.config/dctl/images/python-dev/Dockerfile              ← managed Dockerfile

        ──merge──>

Cache (generated, not edited)
  ~/.cache/dctl/devcontainer/python/devcontainer.json      ← merged output used by dctl ws up

        ──dctl init──>

Project registry
  ~/.config/dctl/projects.yaml                             ← points at merged cache for this project
```

All runtime operations (`dctl image build`, `dctl ws up`, `dctl test`) use only
the user config and cache — never the installed files directly. You can freely
edit the user config files to customize your setup.

### Composable config

The devcontainer config uses a manifest-driven layered merge system. Each
selectable config is defined by a YAML manifest:

```yaml
# python.yaml — declares which layers compose this config
name: python
layers:
  - base      # shared infrastructure (remote user, auth mounts, terminal env)
  - python    # leaf layer (image tag, cache volumes, bootstrap commands)
```

- `base` owns the shared universal infrastructure (remote user, auth mounts, terminal env)
- Optional user layers add personal config (dotfiles, editor mounts)
- The **last layer** in the manifest is the **leaf** — it holds project-specific
  settings and is protected from overwrites on deploy
- All preceding layers are **shared** and reconciled automatically

`dctl init` reads the selected manifest from `~/.config/dctl/devcontainer/<name>.yaml`,
resolves each layer from its `<layer>/devcontainer.json`, merges them in order,
and writes the result under `~/.cache/dctl/devcontainer/` for `dctl ws up`.

Manifests are validated against `schemas/compose.schema.yaml` (JSON Schema
Draft 2020-12). Required field: `layers` (non-empty array of strings).
Optional field: `name`.

## Quick Start

Prerequisites:

- Docker with `buildx`
- Dev Container CLI (`devcontainer`)

```bash
make install
cd ~/projects/my-api
dctl deploy devcontainer python
dctl deploy image python-dev
dctl init --devcontainer python
dctl image build
dctl ws up
dctl ws shell
```

1. `make install` — installs `dctl` and copies images/templates to `~/.local/share/dctl/` (seed sources only)
2. `dctl deploy devcontainer python` — deploys the Python manifest plus its managed shared layers into `~/.config/dctl/devcontainer/`
3. `dctl deploy image python-dev` — deploys the managed Dockerfile into `~/.config/dctl/images/python-dev/`
4. `dctl init --devcontainer python` — merges config to `~/.cache/dctl/`, auto-builds the managed image if missing, and registers the project
5. `dctl image build` — optional rebuild from deployed managed images via an explicit target, the no-arg picker, or `--all`
6. `dctl ws up` — starts the devcontainer using the merged config from `~/.cache/dctl/`
7. `dctl ws shell` — drops you into a shell inside the running container

## Workflow Comparison

Every `dctl` command has a Docker and Dev Container CLI equivalent — `dctl` just removes the boilerplate, flag repetition, and manual config authoring. See the [full workflow comparison](docs/WORKFLOW-COMPARISON.md) for a step-by-step walkthrough with complete commands, pain points, and command counts for all three approaches.

## Config System

`base` owns the shared universal infrastructure:

- `remoteUser` and UID behavior
- readonly `.gitconfig`
- shared auth/config mounts for `gh`, `glab-cli`, and Claude
- base container env for `TERM` and `COLORTERM`

Leaf layers add the project-specific settings:

- the image tag
- language-specific cache volumes
- language-specific `postCreateCommand` entries

`dctl init` reads the selected deployed manifest, resolves each listed layer
from `~/.config/dctl/devcontainer/<layer>/devcontainer.json`, and merges them
in manifest order. Installed manifests and layers under
`~/.local/share/dctl/devcontainers/` are seed sources only; `dctl deploy`
copies them into user config.

### Custom layers

Personal configuration is now opt-in. To add dotfiles, editor mounts, or extra terminal integration, copy [examples/dotfiles/devcontainer.json](/workspaces/devcontainerctl/examples/dotfiles/devcontainer.json) into `~/.config/dctl/devcontainer/dotfiles/devcontainer.json`, edit it for your host paths, then add `dotfiles` to your manifest's `layers`.

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
dctl deploy devcontainer python   # optional: resync managed manifest/layers from install
dctl init
dctl ws reup
```

Edit the user layer or manifest file, rerun `dctl init` to regenerate the cached merged config if needed, then use `dctl ws reup` to recreate the container from that updated cache.

## CLI Reference

### Global options

```bash
dctl --config /path/to/devcontainer.json <command-group> [command]
dctl help
dctl version
```

`--config` overrides config resolution for commands that need a `devcontainer.json`.

### `dctl deploy`

```bash
dctl deploy devcontainer python
dctl deploy image python-dev
dctl deploy --all
dctl deploy --all-devcontainers
dctl deploy --all-images
dctl deploy --list
```

- `devcontainer <name>` deploys one manifest-backed config from `~/.local/share/dctl/devcontainers/` into `~/.config/dctl/devcontainer/`
- `image <name>` deploys one managed image from `~/.local/share/dctl/images/` into `~/.config/dctl/images/`
- `--all`, `--all-devcontainers`, `--all-images` deploy bulk selections
- `--reset` backs up and overwrites shipped files
- `--dry-run` prints the per-file plan and changes nothing
- `--list`, `--list-devcontainers`, `--list-images` show `installed`, `deployed`, or `user-only`

Manifest files are always managed on deploy. Non-leaf manifest layers are
reconciled on every devcontainer deploy, while the leaf layer remains
user-protected unless `--reset` is used.

### `dctl init`

```bash
dctl init --devcontainer python
dctl init --force --devcontainer rust
dctl init
```

- `--devcontainer <name>` selects a deployed manifest from `~/.config/dctl/devcontainer/<name>.yaml`
- `--force` rebuilds the cached merged config and re-registers the project

If the selected devcontainer references a managed image like
`devimg/python-dev:latest`, `dctl init` validates that
`~/.config/dctl/images/python-dev/Dockerfile` exists and automatically builds
the image when it is missing locally.

After registering the project, `dctl init` runs `dctl test` (the workspace
smoke test) and prints a final summary covering the chosen devcontainer,
image status, cache and registry paths, and the smoke-test result. `dctl
init` exits non-zero if the smoke test fails.

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

- **Credential forwarding (GitHub and GitLab):** on every `exec`, `shell`, or `run`, `dctl` extracts tokens and injects them into the container as `GH_TOKEN` and `GITLAB_TOKEN`. The extraction follows a precedence chain:
  - `GH_TOKEN` env var → `GITHUB_TOKEN` env var → `gh auth token` CLI
  - `GITLAB_TOKEN` env var → `glab auth status --show-token` CLI
  - If a CLI is not installed or not authenticated, that token is silently skipped — `dctl` never errors on missing credentials.
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

With no positional image name, `dctl image build` opens an `fzf` picker over
the deployed managed images under `~/.config/dctl/images/` and does not consult
the project registry.

Run `dctl deploy image <name>` or `dctl deploy --all-images` to seed image
configs from installed defaults.

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
Debian trixie-slim
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
| `~/.local/share/dctl/` | Installed assets: Dockerfiles, devcontainer templates, schemas. Seed sources only. | No — only read by `dctl deploy` |
| `~/.config/dctl/` | User config: deployed devcontainer layers, deployed Dockerfiles, project registry, defaults | Yes — sole runtime source for builds, merges, and container operations |
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

`make install` does not write to `~/.config/dctl/` or `~/.cache/dctl/`. Run
`dctl deploy ...` after install to copy managed assets into user config, then
run `dctl init` to register the current project.

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
