# devcontainerctl

A unified `dctl` CLI that composes, builds, and runs devcontainer workspaces from your own configuration in `~/.config/dctl/` — especially useful for running AI coding agents (Claude Code, Codex, OpenCode, Gemini CLI) in safe, isolated sandboxes.

- A one-step project setup flow with `dctl init`, against the manifests that you write.
- Image builds from your own Dockerfiles, parents first.
- A composable config system built around manifest-backed layer stacks and user-editable XDG config.
- Multi-agent workflows with shared containers, token forwarding, and work-clone support.

## What You Get

### Your configuration, your images

`dctl` ships no image, no layer, and no manifest. It reads `~/.config/dctl/`,
and you write it: by hand, with a dotfiles manager, or with home-manager.
Each image and each layer installs what your projects need; each project owns
its own dev environment setup.

| Path | What you put there |
| --- | --- |
| `~/.config/dctl/images/<name>/Dockerfile` | One folder per image; `dctl image build` tags it `devimg/<name>:latest` |
| `~/.config/dctl/devcontainer/<name>.yaml` | One manifest per selectable config, listing its layers in order |
| `~/.config/dctl/devcontainer/<layer>/devcontainer.json` | One folder per layer |
| `~/.config/dctl/projects.yaml` | The project registry, written by `dctl init` |

[docs/examples/](docs/examples/README.md) holds a copyable starting point in
this layout: an `example` image, an `example` manifest, and the `base`,
`agents`, `dotfiles`, and `example` layers. No command reads it, and
`make install` does not install it.

### How `dctl init` works

`dctl init` selects only from the manifests in your user config, builds any
missing managed image, and registers the current project:

```text
User config (runtime source of truth, written by you)
  ~/.config/dctl/devcontainer/example.yaml                 ← manifest
  ~/.config/dctl/devcontainer/base/devcontainer.json       ← shared base layer
  ~/.config/dctl/devcontainer/example/devcontainer.json    ← leaf layer
  ~/.config/dctl/images/example/Dockerfile                 ← managed Dockerfile

        ──dctl init──>

Project registry + managed image
  ~/.config/dctl/projects.yaml                             ← stores the selected manifest name for this project

        ──regenerated fresh on every command──>

Runtime generated (ephemeral, never cached, regenerated in place)
  $XDG_RUNTIME_DIR/dctl/devcontainer/example/devcontainer.json  ← merged output used by dctl ws up/reup/test
```

All runtime operations (`dctl image build`, `dctl ws up`, `dctl test`) use only
the user config. The merged output is regenerated fresh on every command, so
config edits apply immediately.

### Composable config

The devcontainer config uses a manifest-driven layered merge system. Each
selectable config is defined by a YAML manifest:

```yaml
# example.yaml — declares which layers compose this config
layers:
  - base      # shared infrastructure (remote user, auth mounts, terminal env)
  - agents    # shared agents layer (seccomp profile, agent CLI config mounts)
  - example   # leaf layer (image tag, cache volumes)
```

- `base` owns the shared universal infrastructure (remote user, auth mounts, terminal env)
- Optional user layers add personal config (dotfiles, editor mounts)
- The **last layer** in the manifest is the **leaf** — it holds project-specific
  settings
- All preceding layers are **shared**: several manifests can list the same layer

`dctl init` registers the manifest name for the project; the merge itself runs
on demand. Each command that needs the config reads the selected manifest from
`~/.config/dctl/devcontainer/<name>.yaml`, resolves each layer from its
`<layer>/devcontainer.json`, merges them in order, and writes the result fresh
under `$XDG_RUNTIME_DIR/dctl/devcontainer/<name>/devcontainer.json` — never
cached, so layer edits are picked up immediately.

Manifests are validated against `schemas/compose.schema.yaml` (JSON Schema
Draft 2020-12). The only field is `layers` (non-empty array of strings);
the filename stem is the manifest name.

## Quick Start

Prerequisites:

- Docker with `buildx`
- Dev Container CLI (`devcontainer`)

```bash
make install
mkdir -p ~/.config/dctl
cp -r docs/examples/config/dctl/images docs/examples/config/dctl/devcontainer ~/.config/dctl/
cd ~/projects/my-api
dctl init --devcontainer example
dctl image build
dctl ws up
dctl ws shell
```

1. `make install` — installs `dctl`, its shell modules, and the schemas; it writes nothing to `~/.config/dctl/`
2. Write your user config: here, copy the images and devcontainer layers of [docs/examples/](docs/examples/README.md) into `~/.config/dctl/` and edit them for your projects
3. `dctl init --devcontainer example` — registers the project, auto-builds the managed image if missing, and runs the smoke test (`jq` is required for manifest-backed projects)
4. `dctl image build` — optional rebuild of your managed images via an explicit target, the no-arg picker, or `--all`
5. `dctl ws up` — starts the devcontainer, regenerating the merged config fresh under `$XDG_RUNTIME_DIR/dctl/devcontainer/`
6. `dctl ws shell` — drops you into a shell inside the running container

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
- project-specific cache volumes
- project-specific `postCreateCommand` entries

`dctl init` reads the selected manifest, resolves each listed layer
from `~/.config/dctl/devcontainer/<layer>/devcontainer.json`, and merges them
in manifest order.

### Custom layers

Personal configuration is opt-in. To add dotfiles, editor mounts, or extra terminal integration, copy the `dotfiles` layer of [docs/examples/](docs/examples/README.md) into `~/.config/dctl/devcontainer/dotfiles/devcontainer.json`, edit it for your host paths, then add `dotfiles` to your manifest's `layers`.

### Config resolution

`dctl` resolves `devcontainer.json` in this order:

1. `--config` CLI flag
2. `DCTL_CONFIG` environment variable
3. Per-project registry in `~/.config/dctl/projects.yaml` (`devcontainer-manifest: <name>`)
4. Local `.devcontainer/devcontainer.json`
5. Work-clone sibling discovery
6. User global default at `~/.config/dctl/default/devcontainer.json`

### Work-clone workflow

If you work in sibling clones such as `repo/` and `repo.42-add-auth/`, `dctl` can resolve the main repo's config for the work-clone while still keeping the container identity keyed to the current workspace path. That means each clone gets its own container, even when they share config.

### Editing config and applying changes

```bash
$EDITOR ~/.config/dctl/devcontainer/example/devcontainer.json
dctl ws reup
```

Edit the user layer or manifest file, then use `dctl ws reup` to recreate the container. The merged config is regenerated fresh on every `dctl ws up`/`reup`/`test`, so layer edits are picked up immediately — no `dctl init` re-run is needed.

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
dctl init --devcontainer example
dctl init
```

- `--devcontainer <name>` selects a manifest from `~/.config/dctl/devcontainer/<name>.yaml`
- every `dctl init` re-registers the project and applies the legacy `projects.yaml` `devcontainer:` → `devcontainer-manifest:` migration automatically

If the selected devcontainer references a managed image like
`devimg/example:latest`, `dctl init` validates that
`~/.config/dctl/images/example/Dockerfile` exists and automatically builds
the image when it is missing locally.

After registering the project, `dctl init` runs `dctl test` (the workspace
smoke test) and prints a final summary covering the chosen devcontainer,
image status, generated config and registry paths, and the smoke-test result.
`dctl init` exits non-zero if the smoke test fails.

### `dctl ws`

```bash
dctl ws up
dctl ws reup
dctl ws shell
dctl ws shell claude
dctl ws exec -- pytest
dctl ws run -- pytest -q
dctl ws run -- bash -c 'make check && make test'
dctl ws status
dctl ws down
```

`dctl ws shell <cmd>` and `dctl ws run` pass each word to the container as one argument, as you wrote it. A shell expression with `&&`, `|`, or `;` runs only through an explicit shell: `bash -c '...'`.

`dctl ws` adds a few important host-side conveniences:

- **Forge auth forwarding (GitHub and GitLab):** on every `up`, `reup`, `exec`, `shell`, or `run`, `dctl` invokes the host tool `forge-seed` (owned by the user's nix config; see [docs/specs/secret-forwarding/SPEC.md](docs/specs/secret-forwarding/SPEC.md)) to materialize an ephemeral per-project copy of the host `gh`/`glab` config — tokens read via the keyring-aware host CLIs — under `$XDG_RUNTIME_DIR/forge-auth/<project>`, then bind-mounts it into the container at `/run/forge-auth`. The container receives `GH_CONFIG_DIR`/`GLAB_CONFIG_DIR` paths, never a secret: no `GH_TOKEN`/`GITLAB_TOKEN` enters the container environment. The seed dir is a live bind, so a rotated host token reaches an already-running container on the next `exec` with no reup. If `forge-seed` is absent, or a CLI is not installed or not authenticated, that seed is silently skipped — `dctl` never errors on missing credentials.
- **SSH agent forwarding:** when the host exposes a live `SSH_AUTH_SOCK`, `dctl` mounts the socket (never key material) at `/run/dctl/ssh-agent.sock` and points the container's `SSH_AUTH_SOCK` at it, so `git@...` remotes authenticate without any token. A host agent restart replaces the socket inode; running containers hold the dead socket until `dctl ws reup`.
- forwards terminal-related env vars such as `TERM`, `COLORTERM`, `TERM_PROGRAM`, and Kitty-specific vars
- bind-mounts the shared git common dir automatically for linked worktrees

### `dctl image`

```bash
dctl image build
dctl image build example
dctl image build --all
dctl image build --full-rebuild
dctl image build --dry-run
dctl image list
```

`dctl image build` resolves Dockerfiles from user config only:

- `~/.config/dctl/images/<target>/Dockerfile`

With no positional image name, `dctl image build` opens an `fzf` picker over
the managed images under `~/.config/dctl/images/` and does not consult
the project registry.

`dctl` ships no Dockerfile. Add one folder per image with a `Dockerfile` under
`~/.config/dctl/images/`; [docs/examples/](docs/examples/README.md) shows one.

`dctl image build` reads the dependency graph from the `FROM` lines of the
Dockerfiles in your user config and builds every parent before its child, so a family
needs no build order from the operator. The grammar it reads is literal:

- `FROM devimg/<name>:latest` names `<name>` as a managed parent.
- Any other `devimg/` spelling, such as `FROM devimg/base:v2`, is refused.
- Any reference holding `$`, such as `FROM devimg/${PARENT}:latest`, is refused.
- Any other reference is an external base and stays out of the graph.
- A `FROM <alias>` naming a stage of the same file is not an image reference.

A named target always builds. An ancestor pulled in by the graph builds only
when `docker image inspect` does not already find its tag. `--full-rebuild`
builds every name in the graph with `--no-cache`, and pulls each literal
external base by name first. It does not pass `--pull` to `docker buildx
build`, because that flag applies to the whole Dockerfile and would resolve a
local managed parent against a registry.

When a build fails, its descendants are skipped rather than built on the older
parent tag. Independent branches of the graph continue, and the command reports
the complete failed and blocked set before it exits.

`dctl image build --dry-run` computes the same order and needs no Docker
daemon.

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

Your images form a family through their `FROM` lines. A Dockerfile in
`~/.config/dctl/images/<name>/` can start `FROM devimg/<parent>:latest`, and
`dctl image build` builds the parent first:

```text
external base (for example openSUSE Tumbleweed)
        │
        ▼
devimg/base:latest        ← ~/.config/dctl/images/base/Dockerfile
        │
        └── devimg/example:latest   ← ~/.config/dctl/images/example/Dockerfile
```

The names are yours. Each image installs what your projects need.

## XDG Layout

| Directory | Purpose | Used at runtime? |
| --- | --- | --- |
| `~/.local/share/dctl/` | Installed schemas (`schemas/`) | Yes — read to validate manifests and the project registry |
| `~/.config/dctl/` | User config, written by you: devcontainer manifests and layers, Dockerfiles, project registry, defaults | Yes — sole runtime source for builds, merges, and container operations |
| `$XDG_RUNTIME_DIR/dctl/` | Runtime-generated merged `devcontainer.json` output, regenerated fresh on every command and never cached (fallback `${TMPDIR:-/tmp}/dctl-$(id -u)/dctl/`) | Yes — regenerated and consumed by `dctl ws up`/`reup`/`test` |

The first two honor `XDG_DATA_HOME` and `XDG_CONFIG_HOME`; the generated output
honors `XDG_RUNTIME_DIR`.

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
- schema files to `~/.local/share/dctl/schemas/`

`make install` installs no image, no layer, and no manifest, and does not write
to `~/.config/dctl/`. Write your user config there (see
[docs/examples/](docs/examples/README.md) for a starting point), then run
`dctl init` to register the current project.

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

Use `make uninstall` to remove the installed binary, shell modules, and schemas. For one release it also removes the Dockerfiles, devcontainer manifests, and layers that older releases installed under `~/.local/share/dctl/`. Use `make uninstall-systemd` to remove and disable the weekly rebuild timer.

## Development

The flake dev shell is the one source of the tools that `make check`, `make test`, and the git hooks call. `.envrc` loads it with direnv. Run a command in it with the native command of either tool:

```bash
direnv exec . make check      # or: nix develop --command make check
nix develop                   # open a shell inside it
```

Install the git hooks once per clone, from the dev shell. `pre-commit install` installs every stage of `default_install_hook_types` in `.pre-commit-config.yaml` into the shared git folder, so every linked worktree runs them:

```bash
nix develop --command pre-commit install
```

The hooks take their tools from `PATH`, so commit from the dev shell, or with `direnv exec . git commit`. A commit from a shell outside it fails at the first hook whose tool is missing.

## Further Reading

- [QUICKSTART.md](docs/QUICKSTART.md) for a short setup path
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) for deeper technical rationale and troubleshooting
- [spec/README.md](spec/README.md) for the implemented design/spec set
- [slides/](slides/) for the Slidev presentation (`cd slides && npm install && npm run dev`); auto-deployed to GitHub Pages
