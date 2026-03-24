# devcontainerctl

Pre-built Docker images and a unified `dctl` CLI for AI-agent devcontainer sandboxes.

## Image Layers

Three-tier architecture on a shared foundation:

| Image | Base | What it adds |
| --- | --- | --- |
| `devimg/agents` | Debian bookworm-slim | Dev tools, Bun, Rust, mise, Node LTS, neovim, gh, glab, Claude Code, Codex, OpenCode, Gemini CLI |
| `devimg/python-dev` | `devimg/agents` | Poetry via mise (`virtualenvs.in-project = true`) |
| `devimg/rust-dev` | `devimg/agents` | rustup (`--default-toolchain none`) |
| `devimg/zig-dev` | `devimg/agents` | anyzig + minisign + zig-zls-init |

The `agents` base includes rolling Python and Go runtimes for shared tooling. Project-specific runtime versions stay pinned in project config and override the base defaults at container start or first tool invocation.

## Install

```bash
make install

# Optional: install the weekly rebuild timer
make install-systemd
systemctl --user daemon-reload
systemctl --user enable --now dctl-image-build.timer

# Convenience wrapper
./install.sh --systemd
```

`make install` installs:

- `dctl` to `~/.local/bin/dctl`
- shell library to `~/.local/lib/dctl/`
- image Dockerfiles to `~/.local/share/dctl/images/`
- devcontainer templates to `~/.local/share/dctl/templates/`
- project registry schema to `~/.local/share/dctl/schemas/`

`~/.local/bin` must be in `PATH`. The installer warns if it is missing.

`make install` never writes to `~/.config/dctl/` — that directory is reserved for
user-controlled configuration.

## Setup

```bash
# Build all images (requires dotfiles at ~/.dotfiles or $DOTFILES)
dctl image build --all

# Inspect available images
dctl image list

# Scaffold a project from an installed template and validate it
dctl init --template python

# Re-run the setup smoke test later
dctl test
```

## CLI

### Global Options

```bash
dctl --config /path/to/devcontainer.json <command>  # override config resolution
```

The `--config` flag sets the devcontainer.json path for any command that needs it
(`ws up`, `ws reup`, `test`). It takes highest precedence in the resolution chain.

### `dctl init`

```bash
dctl init --template python  # register project with a specific template
dctl init --list             # list available templates
dctl init                    # interactive fzf selector
dctl init --force --template rust
dctl init --no-register --template python  # skip registry registration
```

`dctl init` deploys the selected template to
`~/.config/dctl/devcontainer/<name>/devcontainer.json` and registers it in
`~/.config/dctl/projects.yaml`. The config resolution chain picks up the
deployed config from the registry. Use `--no-register` to skip registration.
Use `--force` to re-deploy and update the registry even if already configured.

If the project is already registered, `dctl init` warns and skips by default,
then runs the smoke test against the existing config.

Templates are discovered from installed templates only:
- `~/.local/share/dctl/templates/` — installed by `make install`

### `dctl test`

```bash
dctl test  # validate prerequisites, build managed images, smoke-test the workspace
```

### `dctl image`

```bash
dctl image build                  # interactive fzf selection
dctl image build agents           # specific image
dctl image build --all            # all images (pulls base updates)
dctl image build --refresh-agents agents  # cache-bust agent CLI layer
dctl image build --full-rebuild   # full uncached rebuild of all images
dctl image build --dry-run        # preview only
dctl image list                   # show available targets
```

The `agents` and `zig-dev` images require the dotfiles repo as a BuildKit named context. Set `DOTFILES=` or ensure `~/.dotfiles` exists.

### `dctl config`

```bash
dctl config            # project registry management (placeholder)
```

The project registry at `~/.config/dctl/projects.yaml` maps canonical project names
to per-project settings (devcontainer path, Dockerfile target, sibling discovery).
See [`spec/10-project-registry.md`](spec/10-project-registry.md) for details.

### `dctl ws`

```bash
dctl ws up             # start devcontainer (resolves config automatically)
dctl ws reup           # recreate after config/image changes
dctl ws shell          # interactive shell
dctl ws exec -- pytest # run command in container
dctl ws run -- claude-session  # run via bash -lc
dctl ws status         # show containers for this project
dctl ws down           # stop and remove
```

When using `dctl ws shell`/`exec`/`run`, tokens are automatically extracted from the host via `gh auth token` and `glab auth status --show-token` and passed into the container as `GH_TOKEN`/`GITLAB_TOKEN` environment variables. This is necessary because modern `gh` (v2.24.0+) stores OAuth tokens in the system keyring, which is inaccessible from containers; `glab` stores tokens in `~/.config/glab-cli/config.yml` by default, but extracting them uniformly via the CLI avoids depending on config file internals. If a CLI is not installed or not authenticated, its token is silently skipped.

If the Claude wrapper wiring inside a container looks broken, recreate the container:

```bash
dctl ws reup
```

## Config Resolution

`dctl` resolves `devcontainer.json` using a precedence chain (highest wins):

1. `--config` CLI flag
2. `DCTL_CONFIG` environment variable
3. Per-project registry (`~/.config/dctl/projects.yaml`)
4. Local workspace file (`.devcontainer/devcontainer.json`)
5. Work-clone sibling discovery
6. User global default (`~/.config/dctl/default/devcontainer.json`)

The resolved config is passed to the Dev Container CLI via `--config`. The
`--workspace-folder` always remains the current directory, preserving per-clone
container identity.

### Work-Clone Workflow

Work-clones are sibling directories named `repo.42-feature` alongside a main `repo/`.
When a work-clone has no local config, `dctl` discovers the main repo's
`.devcontainer/devcontainer.json` automatically:

```bash
# Main repo has the config
~/Projects/repo/.devcontainer/devcontainer.json

# Work-clone uses it automatically
cd ~/Projects/repo.42-add-auth
dctl ws up  # resolves config from ../repo/
```

Each clone gets its own container — only the config is shared.

### Dockerfile Resolution

`dctl image build` resolves Dockerfiles through two layers (user overrides installed):

1. `~/.config/dctl/images/<target>/Dockerfile` — user override
2. `~/.local/share/dctl/images/<target>/Dockerfile` — installed

### XDG Layout

| Directory | Purpose |
| --- | --- |
| `~/.config/dctl/` | User config: project registry, deployed devcontainer configs, image overrides, defaults |
| `~/.local/share/dctl/` | Installed data: templates, images, schemas |

Both honor `XDG_CONFIG_HOME` and `XDG_DATA_HOME`.

## Automation

A systemd user timer rebuilds all images weekly:

| Unit | Purpose |
| --- | --- |
| `dctl-image-build.timer` | Fires Friday 18:00, `Persistent=true` |
| `dctl-image-build.service` | Runs `dctl image build --all` |

## Uninstall

```bash
make uninstall

# Remove the user timer if installed
make uninstall-systemd

# Convenience wrapper
./uninstall.sh --systemd
```

## Workflow Comparison

Each task below is shown three ways — raw Docker, the devcontainer CLI, and `dctl` — so the operational difference is immediately visible.

### Setting Up a New Project

Bootstrap a Python project inside a container:

**Docker:**

```bash
# 1. Write a Dockerfile (FROM, RUN, USER, WORKDIR, …)
# 2. Build the image
docker build -t myproject .

# 3. Start the container
docker run -it \
  -v "$PWD:/workspaces/myproject" \
  -w /workspaces/myproject \
  --name myproject-dev \
  myproject
```

**devcontainer CLI:**

```bash
# 1. Create the config directory and devcontainer.json
mkdir -p .devcontainer
cat > .devcontainer/devcontainer.json <<'JSON'
{
  "name": "myproject-sandbox",
  "image": "devimg/python-dev:latest",
  "remoteUser": "dev",
  "mounts": [
    {
      "source": "poetry-cache",
      "target": "/home/dev/.cache/pypoetry",
      "type": "volume"
    }
  ],
  "postCreateCommand": {
    "python": "bash -ic dev-py",
    "pre-commit": "pre-commit install"
  }
}
JSON

# 2. Start the container
devcontainer up --workspace-folder .
```

**dctl:**

```bash
dctl init --template python
dctl ws up
```

`dctl init` deploys a template to `~/.config/dctl/devcontainer/<name>/devcontainer.json` and registers it in `~/.config/dctl/projects.yaml`. No local files are created — the config resolution chain reads the deployed config from the registry. Built-in templates: `base`, `coordinator`, `python`, `rust`, `zig`.

### Running a Command

Execute a test suite inside the running container:

**Docker:**

```bash
docker exec -it myproject-dev pytest
```

**devcontainer CLI:**

```bash
devcontainer exec --workspace-folder . pytest
```

**dctl:**

```bash
dctl ws exec -- pytest
```

### Interactive Shell

Open a shell session inside the container:

**Docker:**

```bash
docker exec -it myproject-dev bash
```

**devcontainer CLI:**

```bash
devcontainer exec --workspace-folder . bash
```

**dctl:**

```bash
dctl ws shell
```

### Multiple Terminal Sessions

Attach additional terminals to the same running container:

**Docker:**

```bash
# terminal 1
docker exec -it myproject-dev bash

# terminal 2
docker exec -it myproject-dev bash

# terminal 3 — run an agent
docker exec -it myproject-dev claude-session
```

**devcontainer CLI:**

```bash
# terminal 1
devcontainer exec --workspace-folder . bash

# terminal 2
devcontainer exec --workspace-folder . bash

# terminal 3 — run an agent
devcontainer exec --workspace-folder . claude-session
```

**dctl:**

```bash
# terminal 1
dctl ws shell

# terminal 2
dctl ws shell

# terminal 3 — run an agent
dctl ws shell claude-session
```

Each session shares the same container, filesystem, and installed tools.

### Rebuilding After Config or Image Changes

Recreate the container after changing the Dockerfile or devcontainer.json:

**Docker:**

```bash
docker build -t myproject .
docker stop myproject-dev
docker rm myproject-dev
docker run -it \
  -v "$PWD:/workspaces/myproject" \
  -w /workspaces/myproject \
  --name myproject-dev \
  myproject
```

**devcontainer CLI:**

```bash
devcontainer up --workspace-folder . --remove-existing-container
```

**dctl:**

```bash
dctl ws reup
```

### Image Management

Keep base images up to date across projects:

**Docker:**

```bash
# each project maintains its own Dockerfile
cd ~/project-a && docker build -t project-a-dev .
cd ~/project-b && docker build -t project-b-dev .
# repeat for every project…
```

**devcontainer CLI:**

```bash
# no unified image command — each project rebuilds independently
cd ~/project-a && devcontainer up --workspace-folder .
cd ~/project-b && devcontainer up --workspace-folder .
```

The devcontainer CLI has no equivalent of a global image build or image list.

**dctl:**

```bash
dctl image build --all   # rebuild all managed images once
dctl image list          # show available targets
```

`dctl` adds on top of the devcontainer standard:

- Pre-built images with AI agent tools (Claude Code, Codex, Gemini CLI) ready to use.
- Dotfiles integration baked into base image metadata.
- Template system for instant project scaffolding (`dctl init`).
- Config resolution chain for flexible devcontainer.json discovery.
- Work-clone support for parallel feature branches sharing config.
- Per-project registry (`projects.yaml`) for host-side project configuration.
- Dockerfile override hierarchy (user custom over installed).
- Unified CLI for images, workspaces, and lifecycle in one tool.
- Optional systemd timer for weekly unattended image rebuilds.
- Multi-agent support: attach multiple AI agents to the same container.

## Design Specs

Design documents for the config resolution and work-clone support features are in
[`spec/README.md`](spec/README.md). The core resolution chain, project registry,
template discovery, and Dockerfile hierarchy are now implemented.

## Further Reading

- [QUICKSTART.md](docs/QUICKSTART.md) — Project setup templates and common commands
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — Container/image architecture and troubleshooting
