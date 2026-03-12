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

`~/.local/bin` must be in `PATH`. The installer warns if it is missing.

## Setup

```bash
# Build all images (requires dotfiles at ~/.dotfiles or $DOT)
dctl image build --all

# Inspect available images
dctl image list

# Scaffold a project from an installed template and validate it
dctl init --template python

# Re-run the setup smoke test later
dctl test
```

## CLI

### `dctl init`

```bash
dctl init --template python  # scaffold from a specific template
dctl init                    # interactive fzf selector
dctl init --force --template rust
```

If `.devcontainer/devcontainer.json` already exists, `dctl init` warns and keeps
it unchanged by default, then runs the smoke test against the current project.

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

The `agents` and `zig-dev` images require the dotfiles repo as a BuildKit named context. Set `DOT=` or ensure `~/.dotfiles` exists.

### `dctl workspace`

```bash
dctl workspace up             # start devcontainer
dctl workspace reup           # recreate after config/image changes
dctl workspace shell          # interactive shell
dctl workspace exec -- pytest # run command in container
dctl workspace run -- claude-session  # run via bash -lc
dctl workspace status         # show containers for this project
dctl workspace down           # stop and remove
```

If the Claude wrapper wiring inside a container looks broken, recreate the container:

```bash
dctl workspace reup
```

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
dctl workspace up
```

`dctl init` copies a ready-made `devcontainer.json` into `.devcontainer/` with image, mounts, and lifecycle hooks pre-configured.

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
dctl workspace exec -- pytest
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
dctl workspace shell
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
dctl workspace shell

# terminal 2
dctl workspace shell

# terminal 3 — run an agent
dctl workspace shell claude-session
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
dctl workspace reup
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
- Unified CLI for images, workspaces, and lifecycle in one tool.
- Optional systemd timer for weekly unattended image rebuilds.
- Multi-agent support: attach multiple AI agents to the same container.

## Further Reading

- [QUICKSTART.md](docs/QUICKSTART.md) — Project setup templates and common commands
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — Container/image architecture and troubleshooting
