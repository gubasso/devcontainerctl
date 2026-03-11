# Devcontainers for AI Agent Sandboxing

A practical guide to using Dev Containers as isolated, reproducible development environments for running AI coding agents (Claude Code, Codex, OpenCode, Gemini CLI) safely in YOLO mode.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Base Images](#base-images)
5. [Runtime Version Management](#runtime-version-management)
6. [Workspace Setup](#workspace-setup)
7. [Per-Project Configuration](#per-project-configuration)
8. [Mount Strategies](#mount-strategies)
9. [Running Multiple Agents](#running-multiple-agents)
10. [Security Model](#security-model)
11. [Workflows](#workflows)
12. [Image Refresh Workflow](#image-refresh-workflow)
13. [Advanced Configuration](#advanced-configuration)
14. [Troubleshooting](#troubleshooting)
15. [Quick Reference](#quick-reference)
16. [Full Configuration Examples](#full-configuration-examples)

---

## Overview

### What This Setup Provides

- **Reproducible environments**: Define once, use across all projects of the same type
- **Isolation**: Containers can only access explicitly mounted directories
- **Project-pinned runtimes**: Python, Rust, and Zig versions declared in project files, resolved at container creation or first tool invocation
- **Flexible workspace composition**: Mount multiple directories (repos, docs, libs) into a unified `/workspaces`
- **Multi-agent support**: Attach unlimited terminals/agents to the same container
- **YOLO-safe**: Agents have full permissions inside the container, but limited host access
- **Editor-agnostic**: Edit on host with your native editor; container is a headless execution sandbox

### Reproducibility Philosophy

This guide follows a **project-pinned runtime** approach:

| Layer | Strategy | Source of Truth |
| ----- | -------- | --------------- |
| Container image | Rolling (rebuild weekly) | Dockerfiles |
| Python version | Pinned per project | `pyproject.toml [tool.mise]` |
| Rust toolchain | Pinned per project | `rust-toolchain.toml` |
| Zig version | Pinned per project | `build.zig.zon` |
| Dependencies | Pinned per project | `poetry.lock` / `Cargo.lock` |

The `agents` base image includes rolling shared runtimes for container tooling, while project-specific Python, Rust, and Zig versions stay pinned in project config and are resolved at container creation or first tool invocation. Shared volumes cache installed versions across projects, so subsequent containers with the same version start instantly.

### Host Runtime Mirroring

For LSP accuracy, install runtime version managers on the host:

1. **Install mise on host** - Same version manager as container
2. **Install rustup on host** - Same toolchain manager as container
3. **Run `mise install` on host** - Installs Python interpreter for LSP

The Python template creates `.venv/` via `postCreateCommand: { "python": "bash -ic dev-py", "pre-commit": "pre-commit install" }`. Since the project directory is bind-mounted, the host LSP discovers this `.venv/` and uses it for completions and type-checking.

```bash
# On host (one-time setup per project)
cd ~/projects/my-api
mise install                        # Installs Python version for LSP

# Start container - creates .venv/ via the Python template bootstrap
devcontainer up --workspace-folder .

# Now host LSP can use the container-created .venv/
nvim .
```

**Why not run `poetry install` on host?** The `.venv/` is shared via bind mount. Running project bootstrap in both places writes to the same directory, which is redundant. Let the container own the venv; the host just reads it.

### Mental Model

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ HOST                                  CONTAINER                             │
│                                                                             │
│ mise install                          bash -ic dev-py                      │
│   └── Python interpreter for LSP        └── Creates .venv/ in project root │
│                                                                             │
│ nvim ~/projects/my-app/               ${containerWorkspaceFolder}/ (bind mount) │
│   └── LSP reads .venv/ ◄───────────────── .venv/ created here               │
│                                         ├── claude (agent CLI)              │
│                                         ├── pytest / cargo test             │
│                                         └── debug server                    │
└─────────────────────────────────────────────────────────────────────────────┘

Terminal 1: nvim (host) ──────────────► edits files, LSP uses container's .venv/
Terminal 2: claude-code ──────────────► attached to container
Terminal 3: pytest ───────────────────► attached to container
```

---

## Architecture

### Directory Structure

```text
~/
├── .local/share/dctl/images/      # Base image definitions (build once)
│   ├── agents/                    # Agent tools layer (shared)
│   │   └── Dockerfile
│   ├── python-dev/
│   │   └── Dockerfile             # FROM devimg/agents
│   ├── rust-dev/
│   │   └── Dockerfile             # FROM devimg/agents
│   └── zig-dev/
│       └── Dockerfile             # FROM devimg/agents
│
├── projects/
│   ├── project-a/
│   │   ├── .devcontainer/
│   │   │   └── devcontainer.json
│   │   └── pyproject.toml         # Contains [tool.mise] python = "3.11"
│   ├── project-b/
│   │   ├── .devcontainer/
│   │   │   └── devcontainer.json
│   │   └── pyproject.toml         # Contains [tool.mise] python = "3.12"
│   └── project-c/
│       ├── .devcontainer/
│       │   └── devcontainer.json
│       └── rust-toolchain.toml    # Contains channel = "1.75"
│
└── shared-libs/                   # Libraries mounted as context (RO)
    ├── common-utils/
    └── internal-sdk/
```

### Image Layering Strategy

Separate agent tools from language tooling for better caching:

```text
devimg/agents:latest    (Debian bookworm + bun + node LTS + agent CLIs + mise + build deps)
       │
       ├── devimg/python-dev:latest   (poetry via mise; inherits base python, overridden by project pin)
       ├── devimg/rust-dev:latest     (rustup with no default toolchain)
       └── devimg/zig-dev:latest      (anyzig + minisign + zig-zls-init)
```

The `agents` base includes rolling Python and Go runtimes for shared tooling. Project-specific Python versions override the base default via mise, while Rust and Zig versions remain unbaked and resolve from `rust-toolchain.toml` and `build.zig.zon`.

**Note**: This guide covers Python, Rust, and Zig as practical examples. The same pattern extends to polyglot environments (combine layers) or hardened variants (remove sudo, drop capabilities, add `no-new-privileges`). Adapt the Dockerfiles as needed for your use case.

### Image Reuse

```text
devimg/python-dev:latest (base image, rolling base python)
       │
       ├── project-a  ─► container (mise installs python 3.11)
       ├── project-b  ─► container (mise installs python 3.12)
       └── project-c  ─► container (installs python 3.11)
```

Each project gets its own container with its own virtualenv. Python interpreters are installed inside each container when `mise install` runs.

This keeps the default Python setup simpler, but interpreters become ephemeral: rebuilding a container re-downloads its Python runtime unless you add a custom `mise` volume mount back yourself.

---

## Prerequisites

### Install Docker

```bash
# Arch Linux
sudo pacman -S docker docker-buildx
sudo systemctl enable --now docker.service
sudo usermod -aG docker $USER
# Log out and back in

# Verify
docker run --rm hello-world
```

### Install Devcontainer CLI

```bash
# Using Bun (if installed)
bun install -g @devcontainers/cli

# Or using npm (requires Node.js)
npm install -g @devcontainers/cli

devcontainer --version
```

**Note**: If the CLI fails with Bun, fall back to npm.

---

## Base Images

Dockerfiles are installed by `make install` into `~/.local/share/dctl/images/`.

**Source files** (single source of truth):

- [`images/agents/Dockerfile`](../images/agents/Dockerfile)
- [`images/python-dev/Dockerfile`](../images/python-dev/Dockerfile)
- [`images/rust-dev/Dockerfile`](../images/rust-dev/Dockerfile)
- [`images/zig-dev/Dockerfile`](../images/zig-dev/Dockerfile)

### User Naming Convention

The container user is created with the same name as your host `$USER`, and UID/GID are baked in at build time to match the host. This keeps config files (`.gitconfig`, SSH configs, shell rc files) consistent and avoids bind mount permission issues without runtime UID remapping. The `--build-arg USERNAME=$USER --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g)` flags are required when building the agents base image.

### Layer 0: Agent Tools Base (agents/)

Foundation layer using Debian bookworm-slim for broad compatibility and package availability.

**Includes**:

- System packages: git, ripgrep, fd-find (symlinked as fd), fzf, jq, build tools (build-essential, pkg-config)
- [Bun](https://bun.com/) as JavaScript runtime for agent CLIs (curl install - no apt package)
- [Node.js](https://nodejs.org/) LTS via mise (required for bun-installed package shebangs)
- [mise](https://mise.jdx.dev/) for runtime version management
- [GitHub CLI (gh)](https://github.com/cli/cli) for GitHub workflows
- [GitLab CLI (glab)](https://gitlab.com/gitlab-org/cli) for GitLab workflows
- AI agent CLIs:
  - [Claude Code](https://github.com/anthropics/claude-code) (native installer)
  - [Codex CLI](https://github.com/openai/codex) (OpenAI)
  - [OpenCode](https://github.com/opencode-ai/opencode)
  - [Gemini CLI](https://github.com/google-gemini/gemini-cli) (Google)
- Non-root user with passwordless sudo

#### AI Agent CLI Installation Methods

Native installers are preferred over Homebrew in containers (Homebrew adds ~500MB+ overhead and is designed for user environments, not containers).

| Tool | Method | Command |
| ---- | ------ | ------- |
| Claude Code | Native installer | `curl -fsSL https://claude.ai/install.sh \| bash` |
| Codex CLI | npm (via Bun) | `bun install -g @openai/codex` |
| OpenCode | npm (via Bun) | `bun add -g opencode-ai` |
| Gemini CLI | npm (via Node) | `npm install -g @google/gemini-cli@latest` |

#### Platform CLI Installation Methods

| Tool | Method | Command |
| ---- | ------ | ------- |
| gh (GitHub CLI) | Official APT repo | Keyring + `sources.list.d` entry in `images/agents/Dockerfile` |
| glab (GitLab CLI) | mise (GitLab releases) | `mise use --global gitlab:gitlab-org/cli@latest` |

**Notes**:

- Claude Code: Native installer recommended (auto-updates); npm still supported
- Codex CLI: Official install is npm; Bun works via npm compatibility (unofficial)
- OpenCode: Installed from the npm package via Bun in the current image build
- Gemini CLI: Installed globally via npm using the Node runtime already present in `devimg/agents`

**Authentication**:

| Agent | Method |
| ----- | ------ |
| Claude Code | Interactive login (Anthropic subscription) |
| Codex CLI | Interactive login (ChatGPT account) on first run |
| OpenCode | Interactive login (supports multiple providers) |
| Gemini CLI | Interactive login (Google account) or API key |
| gh | `gh auth login` (interactive, GitHub account) |
| glab | `glab auth login` (interactive, GitLab account) |

All listed CLIs authenticate interactively on first run. To persist auth across container recreations, mount the relevant config directories (see [Pattern 6](#pattern-6-config-with-selective-rw-mounts)).

#### Headless Neovim Bootstrap

The agents image pre-bakes Neovim dependencies at build time so first launch is instant:

| Component | Build Command | Fail-Fast Guard |
| --------- | ------------- | --------------- |
| Lazy plugins | `Lazy! restore` (from lockfile) | Non-zero exit |
| Treesitter parsers | `TSUpdateSync` | Log grep for `failed\|error:` |
| Mason tools | `MasonToolsInstallSync` | 5-min timeout + log grep |

A **duplicate preflight** runs before Mason install — the build fails if any `ensure_installed` list in `mason-tool-installer.lua`, `mason-lspconfig.lua`, or `treesitter.lua` contains duplicate entries (duplicates cause hangs or silent errors).

**Manual verification:**

```bash
# Quick duplicate check (run from dotfiles root)
for f in nvim/.config/nvim/lua/plugins/{mason-tool-installer,mason-lspconfig,treesitter}.lua; do
  dupes=$(sed -n '/ensure_installed\s*=\s*{/,/}/p' "$f" | grep -oP '"\K[^"]+' | sort | uniq -d)
  [ -n "$dupes" ] && echo "DUPLICATES in $(basename "$f"): $dupes"
done

# Full headless test (clean state, ~2 min)
XDG_CONFIG_HOME=/path/to/dotfiles/nvim/.config \
XDG_DATA_HOME="$(mktemp -d)" \
XDG_STATE_HOME="$(mktemp -d)" \
XDG_CACHE_HOME="$(mktemp -d)" \
timeout 300 nvim --headless \
  "+Lazy! sync" \
  "+MasonToolsInstallSync" \
  "+lua os.exit(0)"
# Exit 0 = success, 124 = timeout/hang, other = failure
```

### Layer 1: Python Development (python-dev/)

Thin layer extending `devimg/agents:latest`:

- [Poetry](https://python-poetry.org/) via mise (`pipx:poetry`) with `virtualenvs.in-project = true`
- Inherits rolling Python from `devimg/agents`; project-pinned versions from `pyproject.toml` override via mise

### Layer 1: Rust Development (rust-dev/)

Thin layer extending `devimg/agents:latest`:

- rustup with `--default-toolchain none`
- Toolchain auto-installed from `rust-toolchain.toml` on first `cargo` invocation

### Layer 1: Zig Development (zig-dev/)

Thin layer extending `devimg/agents:latest`:

- [anyzig](https://github.com/marler8997/anyzig) multi-version Zig launcher
- [minisign](https://jedisct1.github.io/minisign/) for zls signature verification
- [zig-zls-init](../bin/.local/bin/zig-zls-init) for per-project zls setup
- Zig version pinned per project via `build.zig.zon` (`minimum_zig_version` or `mach_zig_version`)
- zls not globally installed — downloaded per-project by `zig-zls-init`, cached at `~/.local/share/zls/<version>/`

### Build Base Images

Use the provided `dctl image` commands:

```bash
# Interactive selection (fzf)
dctl image build

# Build a specific image
dctl image build agents

# Build all images (non-interactive, pulls base updates for agents)
dctl image build --all

# Cache-bust the agent CLI layer
dctl image build --refresh-agents agents

# Full uncached rebuild of all images
dctl image build --full-rebuild

# Preview what would be built
dctl image build --dry-run
```

Or build manually:

```bash
cd ~/.local/share/dctl/images
DOTFILES_DIR="${DOT:-$HOME/.dotfiles}"
docker buildx build --load --build-context dotfiles="$DOTFILES_DIR" --build-arg USERNAME=$USER --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) -t devimg/agents:latest ./agents/
docker buildx build --load --build-arg USERNAME=$USER --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) -t devimg/python-dev:latest ./python-dev/
docker buildx build --load --build-arg USERNAME=$USER --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) -t devimg/rust-dev:latest ./rust-dev/
docker buildx build --load --build-context dotfiles="$DOTFILES_DIR" --build-arg USERNAME=$USER --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) -t devimg/zig-dev:latest ./zig-dev/
```

The `agents` and `zig-dev` images require the dotfiles repo as a BuildKit named context. Set `DOT=` or ensure `~/.dotfiles` exists before building.

---

## Runtime Version Management

### Philosophy

The `agents` base includes rolling Python and Go runtimes for shared tooling such as neovim providers, pre-commit, and general CLI usage. Project-specific versions override these defaults where applicable:

- **Python**: Declared in `pyproject.toml` via `[tool.mise]`, overriding the base Python via mise during project bootstrap
- **Rust**: Declared in `rust-toolchain.toml`, auto-installed by rustup on first `cargo` invocation
- **Zig**: Declared in `build.zig.zon`, resolved by anyzig on command execution

This keeps the shared image layer reusable while giving each project exact version control. The same config files work for CI and other developers without containers.

### What's Shared vs Isolated

| Component | Scope | Storage |
| --------- | ----- | ------- |
| Python interpreters | Per-container | Installed by `mise install` during container creation |
| Rust toolchains | Shared across projects | `rustup-toolchains` volume |
| Zig global cache | Shared across projects | `zig-cache` volume (`/home/<user>/.cache/zig`) |
| Cargo registry/git | Shared across projects | `cargo-registry`, `cargo-git` volumes |
| zls binaries | Shared across projects | `zls-cache` volume (`/home/<user>/.local/share/zls`) |
| Python virtualenvs | Per-project | `.venv/` in project dir (created by container, read by host LSP) |
| Rust target dirs | Per-project | `target/` in project dir |

### Python Version Management (mise)

#### Project Configuration

Add `[tool.mise]` to your `pyproject.toml`:

```toml
# pyproject.toml

[project]
name = "my-api"
version = "0.1.0"
requires-python = ">=3.11"

[tool.mise]
python = "3.11"

[tool.poetry]
# ... existing poetry config
```

No separate `.python-version` or `.mise.toml` needed—`pyproject.toml` is the single source of truth.

#### Container Configuration

Use `devimg/python-dev:latest` with mise and Poetry cache volumes. See [Standard Python Configuration](#standard-python-configuration) for a complete `devcontainer.json` template.

**Dockerfile**: [`images/python-dev/Dockerfile`](../images/python-dev/Dockerfile)

#### Cold Start Behavior

| Scenario | Time |
| -------- | ---- |
| First container with Python 3.11 | ~30-60s (downloads + builds) |
| Second container with Python 3.11 | Instant (cached in volume) |
| First container with Python 3.12 | ~30-60s (new version) |

### Rust Toolchain Management (rustup)

#### Project Configuration

Create `rust-toolchain.toml` in project root:

```toml
# rust-toolchain.toml

[toolchain]
channel = "1.75"
components = ["rustfmt", "clippy", "rust-analyzer"]
```

Rustup reads this file automatically—no extra commands needed.

#### Container Configuration

Use `devimg/rust-dev:latest` with rustup and cargo cache volumes. See [Standard Rust Configuration](#standard-rust-configuration) for a complete `devcontainer.json` template.

**Dockerfile**: [`images/rust-dev/Dockerfile`](../images/rust-dev/Dockerfile)

#### Cold Start Behavior

| Scenario | Time |
| -------- | ---- |
| First container with Rust 1.75 | ~60-90s (downloads toolchain + components) |
| Second container with Rust 1.75 | Instant (cached in volume) |
| First `cargo build` | Depends on deps (registry cached) |

### Zig Version Management (anyzig)

#### Project Configuration

Pin Zig in `build.zig.zon`:

```zig
.{
  .name = "my-zig-app",
  .version = "0.0.1",
  .minimum_zig_version = "0.15.1",
}
```

Mach projects can use `.mach_zig_version = "<version>-mach"`; when present, it takes priority.

#### Container Configuration

Use `devimg/zig-dev:latest` with Zig and zls cache volumes. `zig-zls-init` sets up project-local zls wiring (`.nvim.lua`) and caches zls per Zig version.

**Dockerfile**: [`images/zig-dev/Dockerfile`](../images/zig-dev/Dockerfile)

#### Typical Flow

```bash
# Bootstrap project with explicit Zig version
zig 0.15.1 init

# Create/update per-project zls setup
zig-zls-init --allow-unsigned --force
```

### Version Management Commands

```bash
# Inside container

# Check active Python version
mise current python
python --version

# Check active Rust version
rustup show
cargo --version

# Check anyzig launcher + resolved Zig
zig any version
zig version

# Manually install a different Python (temporary)
mise install python@3.13
mise use python@3.13  # for current shell

# List installed toolchains
mise list
rustup toolchain list
zig any list-installed
```

---

## Workspace Setup

A key feature of this setup is composing multiple host directories into a unified `/workspaces` inside the container. This lets AI agents see your main repo alongside documentation, related libraries, or other context—all in one place.

### Workspace Composition Model

```text
HOST                                    CONTAINER /workspaces/
─────────────────────────────────────   ─────────────────────────────────
~/projects/my-api/            ────────► my-api/           (rw, bind)
~/projects/my-api-docs/       ────────► docs/             (ro, bind)
~/libs/internal-sdk/          ────────► internal-sdk/     (ro, bind)
~/projects/legacy-service/    ────────► legacy/           (snapshot, rsync)
```

### Directory Mount Types

Each directory in `/workspaces` can be mounted using one of these strategies:

| Mount Type | Use Case | Permissions | Symlink Behavior | Container Startup |
| ---------- | -------- | ----------- | ---------------- | ----------------- |
| **Bind (rw)** | Main working repo | Read/write | Preserved (may break) | Instant |
| **Bind (ro)** | Reference docs, libs | Read-only | Preserved (may break) | Instant |
| **Rsync snapshot** | Context with symlinks, large read-only refs | Read/write in container | Resolved (copied) | Slower (copy time) |
| **Volume** | Caches, ephemeral data | Read/write | N/A | Instant |

### Mount Type Details

#### Bind Mount (Read/Write)

Standard Docker bind mount. Changes in container reflect on host immediately.

```jsonc
{
  "mounts": [
    "source=${localEnv:HOME}/projects/my-api,target=/workspaces/my-api,type=bind"
  ]
}
```

**When to use**: Main project repo where you need bidirectional sync.

**Tradeoffs**:

- Symlinks pointing outside the mounted tree will break inside the container
- For file mounts, if the container target path is a symlink, Docker follows it and mounts over the symlink target (can clobber binaries unexpectedly)
- File permissions are shared (can cause issues with generated files)

#### Bind Mount (Read-Only)

Same as above, but container cannot modify files.

```jsonc
{
  "mounts": [
    "source=${localEnv:HOME}/projects/my-api-docs,target=/workspaces/docs,type=bind,readonly"
  ]
}
```

**When to use**: Documentation, reference code, or libraries you want agents to read but not modify.

**Tradeoffs**:

- Same symlink limitations as rw bind
- Agent cannot create scratch files in this tree (must use another location)

#### Rsync Snapshot

Copies the entire directory tree into the container at startup, resolving symlinks. The container gets an independent copy that it can freely modify without affecting the host.

```jsonc
{
  "mounts": [
    "source=${localEnv:HOME}/libs/complex-sdk,target=/mnt/src-complex-sdk,type=bind,readonly"
  ],
  "postCreateCommand": "rsync -aL --delete /mnt/src-complex-sdk/ /workspaces/complex-sdk/"
}
```

**Flags explained**:

- `-a`: Archive mode (preserves permissions, timestamps)
- `-L`: Transform symlinks into referent files/dirs (copies the target, not the link)
- `--delete`: Remove files in destination not in source (clean sync)

**When to use**:

- Source tree contains symlinks pointing outside the tree
- You want a point-in-time snapshot the agent can freely modify
- Large reference codebases where you want container-local access speed

**Tradeoffs**:

- Container startup is slower (copy time proportional to size)
- Changes are not synced back to host (by design)
- Consumes container disk space

#### Rsync Snapshot with Exclusions

For large trees, exclude build artifacts and dependencies:

```jsonc
{
  "mounts": [
    "source=${localEnv:HOME}/projects/monorepo,target=/mnt/src-monorepo,type=bind,readonly"
  ],
  "postCreateCommand": "rsync -aL --delete --exclude='node_modules' --exclude='.git' --exclude='target' --exclude='__pycache__' /mnt/src-monorepo/ /workspaces/monorepo/"
}
```

### Workspace Layout Best Practices

1. **Main repo first**: Mount your primary working directory as the first entry in `/workspaces`

2. **Use consistent naming**: Keep container paths predictable:

   ```text
   /workspaces/
   ├── main/           # or use actual repo name
   ├── docs/
   ├── libs/
   │   ├── sdk-a/
   │   └── sdk-b/
   └── refs/           # reference implementations
   ```

3. **Read-only by default**: Mount context directories as read-only unless you specifically need writes

4. **Rsync for symlink-heavy trees**: If a directory contains symlinks pointing outside its tree, use rsync snapshot

5. **Avoid overlapping mounts**: Don't mount `/workspaces/foo` and `/workspaces/foo/bar` separately—mount the parent and let the child be included

6. **Keep `/workspaces` as root** (multi-directory layouts): All project content should live under `/workspaces` for agent consistency

### Refreshing Rsync Snapshots

Rsync snapshots are created at container creation (`postCreateCommand`). To refresh:

```bash
# Option 1: Recreate container
cd ~/projects/my-api
docker ps -aq --filter "label=devcontainer.local_folder=$(pwd -P)" | xargs -r docker rm -f
devcontainer up --workspace-folder .

# Option 2: Manual rsync inside running container
devcontainer exec --workspace-folder . \
  rsync -aL --delete /mnt/src-legacy-sdk/ /workspaces/legacy-sdk/
```

### Workspace Setup Decision Tree

```text
Need to edit files and sync to host?
├── Yes → Bind mount (rw)
└── No → Read-only access sufficient?
    ├── Yes → Does source contain external symlinks?
    │   ├── Yes → Rsync snapshot
    │   └── No → Bind mount (ro)
    └── No (need scratch space) → Rsync snapshot
```

---

## Per-Project Configuration

Shared auth/editor mounts, baseline container settings, and the dotfiles
bootstrap hook are inherited from the `devimg/agents` image label. The examples
below show only project-local deltas.

### Standard Python Configuration

```jsonc
// project-a/.devcontainer/devcontainer.json
{
  "name": "${localWorkspaceFolderBasename}-sandbox",
  "image": "devimg/python-dev:latest",
  "mounts": [
    // python caches
    {
      "source": "mise-cache",
      "target": "${localEnv:HOME}/.local/share/mise",
      "type": "volume"
    },
    {
      "source": "poetry-cache",
      "target": "${localEnv:HOME}/.cache/pypoetry",
      "type": "volume"
    }
  ],
  "postCreateCommand": {
    "python": "bash -ic dev-py",
    "pre-commit": "pre-commit install"
  }
}
```

### Standard Rust Configuration

```jsonc
{
  "name": "${localWorkspaceFolderBasename}-sandbox",
  "image": "devimg/rust-dev:latest",
  "mounts": [
    // rust caches
    {
      "source": "rustup-toolchains",
      "target": "${localEnv:HOME}/.rustup",
      "type": "volume"
    },
    {
      "source": "cargo-registry",
      "target": "${localEnv:HOME}/.cargo/registry",
      "type": "volume"
    },
    {
      "source": "cargo-git",
      "target": "${localEnv:HOME}/.cargo/git",
      "type": "volume"
    }
  ],
  "postCreateCommand": {
    "rust": "cargo build",
    "pre-commit": "pre-commit install"
  }
}
```

### Standard Zig Configuration

```jsonc
{
  "name": "${localWorkspaceFolderBasename}-sandbox",
  "image": "devimg/zig-dev:latest",
  "mounts": [
    // zig caches
    {
      "source": "zig-cache",
      "target": "${localEnv:HOME}/.cache/zig",
      "type": "volume"
    },
    {
      "source": "zls-cache",
      "target": "${localEnv:HOME}/.local/share/zls",
      "type": "volume"
    }
  ],
  "postCreateCommand": {
    "zig-zls": "zig-zls-init --allow-unsigned || true",
    "pre-commit": "pre-commit install"
  }
}
```

### With Git/SSH Config

```jsonc
{
  "name": "project-a",
  "image": "devimg/python-dev:latest",

  "mounts": [
    "source=poetry-cache,target=/home/${localEnv:USER}/.cache/pypoetry,type=volume",

    "source=${localEnv:HOME}/.ssh/known_hosts,target=/home/${localEnv:USER}/.ssh/known_hosts,type=bind,readonly"
  ],

  "postCreateCommand": {
    "python": "bash -ic dev-py",
    "pre-commit": "pre-commit install"
  }
}
```

### With Additional Project Mounts

The automatic workspace mount handles the main project (mounted to
`/workspaces/<basename>`). Use `mounts` to place additional repositories
alongside it.

```jsonc
{
  "name": "project-a",
  "image": "devimg/python-dev:latest",

  "mounts": [
    "source=poetry-cache,target=/home/${localEnv:USER}/.cache/pypoetry,type=volume",
    "source=${localEnv:HOME}/projects/shared-lib,target=/workspaces/shared-lib,type=bind,readonly"
  ],

  "postCreateCommand": {
    "python": "bash -ic dev-py",
    "pre-commit": "pre-commit install"
  }
}
```

### Base Configuration Reuse via Image Labels

The `devimg/agents` base image embeds default devcontainer metadata in a Docker label. Child images (`python-dev`, `rust-dev`, `zig-dev`) inherit it automatically. Per-project `devcontainer.json` files only need project-specific fields — inherited defaults are merged at container creation time.

**Defaults baked into `devimg/agents`:**

| Property | Value | Notes |
| -------- | ----- | ----- |
| `remoteUser` | `${localEnv:USER}` | Matches host username |
| `updateRemoteUserUID` | `false` | UID/GID baked at build time |
| `init` | `true` | Proper init process (PID 1 reaping) |
| `shutdownAction` | `"none"` | Container keeps running after detach |
| `containerEnv` | `TERM`, `COLORTERM` | Propagates host terminal defaults |
| `mounts` | gitconfig, DOT, Claude, gcloud, Codex, OpenCode, Gemini, nvim | Shared auth/editor mounts |
| `postCreateCommand` | `${localEnv:DOT}/.devcontainer/setup-dotfiles ${localEnv:DOT}` | Shared dotfiles bootstrap |

**NOT in the label** (set per project when needed):

- `workspaceMount` — not supported in image labels per spec; always omit in image/Dockerfile mode to use the automatic mount
- `workspaceFolder` — not supported in image labels per spec; always omit in image/Dockerfile mode; set explicitly only in Docker Compose mode

**Merge rule**:

- scalar/object properties like `remoteUser`, `containerEnv`, and `shutdownAction` resolve with `devcontainer.json` considered last
- `mounts` are collected across sources, with later conflicting targets winning
- lifecycle hooks are collected from image metadata and `devcontainer.json`; object-form keys only control parallelism within one hook entry and are not merged by key

After modifying the label, rebuild all images:

```bash
dctl image build agents python-dev rust-dev zig-dev
```

---

## Mount Strategies

### Mount Syntax

```jsonc
{
  "mounts": [
    "source=/host/path,target=/container/path,type=bind",
    "source=/host/path,target=/container/path,type=bind,readonly",
    "source=myvolume,target=/container/path,type=volume",
    "type=tmpfs,target=/container/tmp"
  ]
}
```

### Common Patterns

#### Pattern 1: Runtime + Cache Volumes (Python)

```jsonc
{
  "mounts": [
    "source=poetry-cache,target=/home/${localEnv:USER}/.cache/pypoetry,type=volume",
    "source=pip-cache,target=/home/${localEnv:USER}/.cache/pip,type=volume"
  ]
}
```

#### Pattern 2: Runtime + Cache Volumes (Rust)

```jsonc
{
  "mounts": [
    "source=rustup-toolchains,target=/home/${localEnv:USER}/.rustup,type=volume",
    "source=cargo-registry,target=/home/${localEnv:USER}/.cargo/registry,type=volume",
    "source=cargo-git,target=/home/${localEnv:USER}/.cargo/git,type=volume"
  ]
}
```

#### Cache Volume Hygiene

For truly untrusted sessions, prefer **per-project cache volumes**:

```jsonc
{
  "mounts": [
    "source=poetry-cache-project-a,target=/home/${localEnv:USER}/.cache/pypoetry,type=volume"
  ]
}
```

Wipe caches when needed:

```bash
docker volume rm poetry-cache-project-a 2>/dev/null || true
```

#### Pattern 3: Project + Shared Libraries (RO)

```jsonc
{
  "mounts": [
    "source=poetry-cache,target=/home/${localEnv:USER}/.cache/pypoetry,type=volume",
    "source=${localEnv:HOME}/libs/common,target=/workspaces/libs/common,type=bind,readonly",
    "source=${localEnv:HOME}/libs/sdk,target=/workspaces/libs/sdk,type=bind,readonly"
  ]
}
```

#### Pattern 4: Minimal SSH Config

```jsonc
{
  "mounts": [
    "source=${localEnv:HOME}/.ssh/known_hosts,target=/home/${localEnv:USER}/.ssh/known_hosts,type=bind,readonly"
  ]
}
```

If you need SSH key access:

```jsonc
{
  "mounts": [
    "source=${localEnv:HOME}/.ssh/deploy_key,target=/home/${localEnv:USER}/.ssh/id_ed25519,type=bind,readonly",
    "source=${localEnv:HOME}/.ssh/known_hosts,target=/home/${localEnv:USER}/.ssh/known_hosts,type=bind,readonly"
  ]
}
```

**Security notes**:

- Mounting all of `~/.ssh` gives the agent access to all your SSH keys
- If you mount **any** private key, assume the agent can **exfiltrate it** (agents require outbound network)
- Ensure mounted key files are `chmod 600` on the host

#### Pattern 5: Rsync Snapshot for Symlink-Heavy Sources

```jsonc
{
  "mounts": [
    "source=${localEnv:HOME}/libs/complex-lib,target=/mnt/src-complex-lib,type=bind,readonly"
  ],
  "postCreateCommand": "rsync -aL --delete /mnt/src-complex-lib/ /workspaces/complex-lib/"
}
```

#### Pattern 6: ~/.config with Selective RW Mounts

Rsync most of `~/.config` as read-only snapshot, but bind-mount agent config directories read-write so agents can persist their settings:

```jsonc
{
  "mounts": [
    // Source for rsync (entire .config)
    "source=${localEnv:HOME}/.config,target=/mnt/src-config,type=bind,readonly",

    // Agent configs that need persistence (bind mounts overlay rsync destination)
    "source=${localEnv:HOME}/.config/claude,target=/home/${localEnv:USER}/.config/claude,type=bind",
    "source=${localEnv:HOME}/.config/codex,target=/home/${localEnv:USER}/.config/codex,type=bind"
  ],

  // Rsync runs AFTER mounts; excludes prevent clobbering the bind-mounted dirs
  "postCreateCommand": "rsync -aL --delete --exclude='claude' --exclude='codex' /mnt/src-config/ /home/${localEnv:USER}/.config/"
}
```

**How it works**:

1. All mounts are applied at container creation (bind mounts for claude/codex are active)
2. `postCreateCommand` runs rsync, copying everything except excluded dirs to container's `~/.config`
3. The exclude flags prevent rsync from touching the bind-mounted directories

**When to use**: When agents need access to host tool configs (git, etc.) but also need to persist their own settings back to the host.

---

## Running Multiple Agents

### Container Lifecycle

Use `dctl workspace` for normal lifecycle operations. Raw `devcontainer` and `docker` commands remain available when needed.

### Start Container

```bash
cd ~/projects/project-a
dctl workspace up
```

### Find Container(s)

```bash
cd ~/projects/project-a
dctl workspace status
```

### Attach Multiple Agents

```bash
cd ~/projects/project-a

# Multiple agent sessions
dctl workspace run -- claude-session
dctl workspace run -- claude-session

# Interactive shell
dctl workspace shell
```

### Stop/Remove Container(s)

```bash
cd ~/projects/project-a
dctl workspace down
```

### Compose Projects

```bash
docker compose -f .devcontainer/docker-compose.yml down
```

---

## Security Model

### Default Security Profile

- `sudo NOPASSWD` available
- Safety comes from **mount hygiene**

```jsonc
{
  "image": "devimg/python-dev:latest",

  "privileged": false,

  "mounts": [
    "source=poetry-cache,target=/home/${localEnv:USER}/.cache/pypoetry,type=volume"
  ]
}
```

**Protects against**:

- Reading host files you did not mount
- Docker daemon control (if you don't mount docker.sock)

**Does NOT protect against**:

- Exfiltration of any readable mounted secret over the network
- Root inside the container reading all mounted secrets

**Hardening options** (not covered in detail): For higher security, create image variants that remove sudo, add `no-new-privileges`, and drop all capabilities via `--cap-drop=ALL`.

### What's Isolated

| Resource | Isolated? | Notes |
| -------- | --------- | ----- |
| Filesystem | ✅ | Only mounted paths visible |
| Processes | ✅ | Container has its own PID namespace |
| Network | ⚠️ | Outbound internet allowed (bridge/NAT) |
| Users | ✅ | Separate user namespace; UID/GID matched for bind mount compatibility |
| Capabilities | ✅ | Reduced by default |

### What to NEVER Do

```jsonc
{
  "privileged": true,
  "mounts": [
    "source=/,target=/host,type=bind",
    "source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind",
    "source=${localEnv:HOME},target=/home/${localEnv:USER}/host-home,type=bind"
  ]
}
```

### Network Access

AI agents require outbound internet for their APIs. Containers use bridge/NAT by default.

### UID/GID Mapping

UID/GID are baked into the image at build time via `--build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g)`. This avoids the need for `updateRemoteUserUID: true`, which generates a secondary Dockerfile at runtime and triggers BuildKit warnings with newer Docker versions.

---

## Workflows

### Workflow Wrapper (`dctl workspace`)

`dctl workspace` is installed by the `devcontainerctl` package and wraps the most common per-project lifecycle commands:

```bash
dctl workspace up             # Start current project container
dctl workspace reup           # Recreate after devcontainer.json/image changes
dctl workspace shell          # Open interactive bash shell
dctl workspace run -- claude-session  # Run command via bash -lc
dctl workspace exec -- id     # Run direct command in container
dctl workspace status         # Show matching container(s)
dctl workspace down           # Remove matching container(s)
```

### Workflow 1: New Project Setup

```bash
mkdir -p ~/projects/new-project
cd ~/projects/new-project
git init

# Create pyproject.toml with mise config
cat > pyproject.toml << 'EOF'
[project]
name = "new-project"
version = "0.1.0"
requires-python = ">=3.11"

[tool.mise]
python = "3.11"

[tool.poetry]
name = "new-project"
version = "0.1.0"
EOF

mkdir -p .devcontainer
cat > .devcontainer/devcontainer.json << EOF
{
  "name": "new-project",
  "image": "devimg/python-dev:latest",
  "postCreateCommand": {
    "python": "bash -ic dev-py",
    "pre-commit": "pre-commit install"
  },
  "mounts": [
    "source=poetry-cache,target=/home/\${localEnv:USER}/.cache/pypoetry,type=volume"
  ]
}
EOF

# Host: install Python interpreter for LSP
mise install

# Start container (creates .venv/ via the Python template bootstrap)
dctl workspace up
dctl workspace run -- claude-session  # Interactive login on first run

# Now open editor - LSP will use container-created .venv/
nvim .
```

### Workflow 2: Daily Development

```bash
cd ~/projects/project-a

# Start container first (ensures .venv/ exists for LSP)
dctl workspace up

# Terminal 1: editor on host (LSP uses container-created .venv/)
nvim .

# Terminal 2: agent in container
dctl workspace run -- claude-session

# Terminal 3: tests in container
dctl workspace run -- pytest

# When done
dctl workspace down
```

### Workflow 3: Add Mount Mid-Session

```bash
# Stop container
dctl workspace down

# Edit .devcontainer/devcontainer.json mounts, then restart
dctl workspace reup
dctl workspace run -- claude-session
```

### Workflow 4: Multi-Directory Workspace Setup

Open the devcontainer from the main project directory (`my-api`). The automatic
mount places it at `/workspaces/my-api`; additional repos are added via `mounts`.

```bash
cd ~/projects/my-api
mkdir -p .devcontainer

cat > .devcontainer/devcontainer.json << EOF
{
  "name": "my-api-workspace",
  "image": "devimg/python-dev:latest",
  "mounts": [
    "source=\${localEnv:HOME}/projects/my-api-docs,target=/workspaces/docs,type=bind,readonly",
    "source=\${localEnv:HOME}/libs/internal-sdk,target=/workspaces/sdk,type=bind,readonly",
    "source=poetry-cache,target=/home/\${localEnv:USER}/.cache/pypoetry,type=volume"
  ],
  "postCreateCommand": {
    "python": "bash -ic dev-py",
    "pre-commit": "pre-commit install"
  }
}
EOF

dctl workspace up
dctl workspace run -- claude-session  # Interactive login on first run
```

---

## Image Refresh Workflow

### Weekly Refresh (Recommended)

```bash
dctl image build --all
```

`dctl image build --all` pulls base updates for the `agents` layer and rebuilds all child images.

### Update Running Projects

```bash
cd ~/projects/project-a
dctl workspace reup
```

### Automation (Optional)

```bash
make install-systemd
systemctl --user daemon-reload
systemctl --user enable --now dctl-image-build.timer
```

---

## Advanced Configuration

### Custom Dockerfile per Project

```jsonc
{
  "name": "project-with-custom-deps",
  "build": {
    "dockerfile": "Dockerfile",
    "context": ".."
  }
}
```

```dockerfile
FROM devimg/python-dev:latest

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    && rm -rf /var/lib/apt/lists/*
USER $USERNAME
```

### Docker Compose for Multi-Container

**Note**: Docker Compose mode does not automatically read `devcontainer.metadata` image labels. Properties inherited from labels in single-container mode must be set explicitly in the compose `devcontainer.json`.

```jsonc
{
  "name": "project-with-services",
  "dockerComposeFile": "docker-compose.yml",
  "service": "app",
  "workspaceFolder": "/workspaces/<project-name>",
  "init": true,
  "shutdownAction": "none",
  "remoteUser": "${localEnv:USER}",
  "updateRemoteUserUID": false,
  "overrideCommand": true
}
```

```yaml
# .devcontainer/docker-compose.yml
services:
  app:
    image: devimg/python-dev:latest
    volumes:
      - ..:/workspaces/<project-name>
      - ~/.gitconfig:/home/${USER}/.gitconfig:ro
      - poetry-cache:/home/${USER}/.cache/pypoetry
    environment:
      - DATABASE_URL=postgresql://postgres:postgres@db:5432/dev
    depends_on:
      - db
      - redis

  db:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: dev
    volumes:
      - postgres-data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine

volumes:
  postgres-data:
  poetry-cache:
```

### Features (Pre-built Extensions)

```jsonc
{
  "name": "project",
  "image": "devimg/python-dev:latest",

  "features": {
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "ghcr.io/devcontainers/features/aws-cli:1": {}
  }
}
```

See available features: <https://containers.dev/features>

### GPU Support (NVIDIA)

```jsonc
{
  "name": "gpu-project",
  "image": "devimg/python-dev:latest",

  "runArgs": ["--gpus=all"],
  "containerEnv": {
    "NVIDIA_VISIBLE_DEVICES": "all"
  }
}
```

Requires: nvidia-container-toolkit installed on host.

---

## Troubleshooting

### Container Won't Start

```bash
devcontainer up --workspace-folder . 2>&1 | tee /tmp/devcontainer.log
```

Common issues:

- Image missing: `docker images | grep devimg`
- Port conflict: check `runArgs` for `-p`
- Mount source path missing on host
- Username mismatch: rebuild images with `--build-arg USERNAME=$USER`

### Permission Denied on Mounts

```bash
# Host
id

# Container
devcontainer exec --workspace-folder . id
```

UID/GID should match if the image was built with the correct `USER_UID`/`USER_GID` build args. Rebuild with `dctl image build agents` (and child images as needed) if they don't match.

### Cache Volume Permission Issues

If caches were created with a different UID/GID:

```bash
docker volume rm poetry-cache rustup-toolchains cargo-registry cargo-git zig-cache zls-cache
```

### mise Install Fails

```bash
# Inside container
devcontainer exec --workspace-folder . bash -lc "mise doctor"

# Check pyproject.toml has valid [tool.mise] section
cat pyproject.toml | grep -A2 '\[tool.mise\]'
```

### Rust Toolchain Not Installing

```bash
# Inside container
devcontainer exec --workspace-folder . bash -lc "rustup show"

# Check rust-toolchain.toml exists and is valid
cat rust-toolchain.toml
```

### SSH Key Permission Denied

```bash
chmod 600 ~/.ssh/deploy_key
```

### Agent Can't Connect to API

```bash
# Check network connectivity
devcontainer exec --workspace-folder . curl -I https://api.anthropic.com

# Re-run interactive login if needed
devcontainer exec --workspace-folder . bash -lc "claude-session"
```

### Find Running Containers

```bash
PROJECT_DIR="$(pwd -P)"
docker ps -a --filter "label=devcontainer.local_folder=$PROJECT_DIR"
```

### Rsync Snapshot Not Updating

```bash
# Recreate container
docker ps -aq --filter "label=devcontainer.local_folder=$(pwd -P)" | xargs -r docker rm -f
devcontainer up --workspace-folder .

# Or manual refresh inside container
devcontainer exec --workspace-folder . \
  rsync -aL --delete /mnt/src-legacy-sdk/ /workspaces/legacy-sdk/
```

### Symlinks Broken in Container

If symlinks point outside the mounted tree, use rsync snapshot with `-L` flag.

### Reset Everything

```bash
# Stop/remove all devcontainer-labeled containers
docker ps -aq --filter "label=devcontainer.local_folder" | xargs -r docker rm -f

# Remove all cache volumes
docker volume rm mise-cache poetry-cache pip-cache rustup-toolchains cargo-registry cargo-git zig-cache zls-cache 2>/dev/null || true

# Prune dangling volumes
docker volume prune

# Rebuild from scratch
DOTFILES_DIR="${DOT:-$HOME/.dotfiles}"
docker buildx build --load --pull --no-cache --build-context dotfiles="$DOTFILES_DIR" --build-arg USERNAME=$USER --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) -t devimg/agents:latest ~/.local/share/dctl/images/agents/
docker buildx build --load --no-cache --build-arg USERNAME=$USER --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) -t devimg/python-dev:latest ~/.local/share/dctl/images/python-dev/
docker buildx build --load --no-cache --build-arg USERNAME=$USER --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) -t devimg/rust-dev:latest ~/.local/share/dctl/images/rust-dev/
docker buildx build --load --no-cache --build-context dotfiles="$DOTFILES_DIR" --build-arg USERNAME=$USER --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) -t devimg/zig-dev:latest ~/.local/share/dctl/images/zig-dev/
```

---

## Quick Reference

### Commands

```bash
# Start container
dctl workspace up

# Recreate container
dctl workspace reup

# Attach shell
dctl workspace shell

# Execute command
dctl workspace run -- cmd

# Show container details
dctl workspace status

# Stop/remove container
dctl workspace down

# Rebuild images
dctl image build --all
```

### Files

| File | Purpose |
| ---- | ------- |
| `~/.local/share/dctl/images/*/Dockerfile` | Base image definitions |
| `project/.devcontainer/devcontainer.json` | Per-project container config |
| `project/pyproject.toml` | Python version (`[tool.mise]`) + deps |
| `project/rust-toolchain.toml` | Rust toolchain version |
| `project/build.zig.zon` | Zig version for anyzig resolution |

### Key devcontainer.json Fields

| Field | Purpose |
| ----- | ------- |
| `image` | Base image to use |
| `workspaceFolder` | Working directory inside container (only needed in Docker Compose mode) |
| `mounts` | Additional bind mounts and volumes |
| `containerEnv` | Environment variables |
| `postCreateCommand` | Run once after container creation |
| `remoteUser` | User to run as (inherited from image label) |
| `updateRemoteUserUID` | Map container UID to host UID (inherited from image label) |
| `init` | Use proper init process (inherited from image label) |
| `shutdownAction` | What to do when closed (inherited from image label) |

### Volume Reference

| Volume | Contents | Shared? |
| ------ | -------- | ------- |
| `poetry-cache` | Poetry package cache | Yes |
| `rustup-toolchains` | Rust toolchains | Yes |
| `cargo-registry` | Crates.io index + crates | Yes |
| `cargo-git` | Git-based dependencies | Yes |
| `zig-cache` | Zig global cache | Yes |
| `zls-cache` | zls binaries | Yes |

### Mount Types

| Type | Syntax | Use Case |
| ---- | ------ | -------- |
| Bind (rw) | `source=...,target=...,type=bind` | Main working repo |
| Bind (ro) | `source=...,target=...,type=bind,readonly` | Reference docs/libs |
| Rsync | `postCreateCommand: rsync -aL ...` | Symlink-heavy sources |
| Volume | `source=name,target=...,type=volume` | Caches, toolchains |

### Project Config Files

**Python** (`pyproject.toml`):

```toml
[tool.mise]
python = "3.11"
```

**Rust** (`rust-toolchain.toml`):

```toml
[toolchain]
channel = "1.75"
components = ["rustfmt", "clippy", "rust-analyzer"]
```

---

## Full Configuration Examples

Complete `devcontainer.json` examples demonstrating multi-directory workspaces.
Each project uses the default automatic workspace mount for the main repository.
These rely on the shared defaults baked into `devimg/agents`. For base image
Dockerfiles, see [`images/`](../images/).

### Example 1: API Project with Docs and SDK

Open from the `my-api` project directory.

```jsonc
{
  "name": "my-api-workspace",
  "image": "devimg/python-dev:latest",

  "mounts": [
    // Documentation (read-only context)
    "source=${localEnv:HOME}/projects/my-api-docs,target=/workspaces/docs,type=bind,readonly",

    // Internal SDK (read-only context)
    "source=${localEnv:HOME}/libs/internal-sdk,target=/workspaces/internal-sdk,type=bind,readonly",

    // Cache volumes
    "source=poetry-cache,target=/home/${localEnv:USER}/.cache/pypoetry,type=volume"
  ],

  "postCreateCommand": {
    "python": "bash -ic dev-py",
    "pre-commit": "pre-commit install"
  }
}
```

### Example 2: Workspace with Rsync Snapshot

Open from the `my-api` project directory. The rsync snapshot copies a
symlink-heavy SDK into a flat directory at container creation time.

```jsonc
{
  "name": "my-api-workspace",
  "image": "devimg/python-dev:latest",

  "mounts": [
    // Source for rsync (temporary mount point)
    "source=${localEnv:HOME}/libs/legacy-sdk,target=/mnt/src-legacy-sdk,type=bind,readonly",

    // Cache volumes
    "source=poetry-cache,target=/home/${localEnv:USER}/.cache/pypoetry,type=volume"
  ],

  // Snapshot legacy-sdk into /workspaces (resolves symlinks), then setup project
  "postCreateCommand": {
    "rsync-sdk": "rsync -aL --delete /mnt/src-legacy-sdk/ /workspaces/legacy-sdk/",
    "python": "bash -ic dev-py",
    "pre-commit": "pre-commit install"
  }
}
```

### Example 3: Monorepo with Selective Mounts

Create a wrapper directory containing only the `.devcontainer/` config, then
open from that directory. The automatic mount places the wrapper at
`/workspaces/<wrapper-name>`; selective bind mounts bring in individual
monorepo packages alongside it.

```jsonc
{
  "name": "feature-workspace",
  "image": "devimg/python-dev:latest",

  "mounts": [
    // Only the packages you're working on (read/write)
    "source=${localEnv:HOME}/monorepo/packages/auth,target=/workspaces/auth,type=bind",
    "source=${localEnv:HOME}/monorepo/packages/api,target=/workspaces/api,type=bind",

    // Shared types (read-only)
    "source=${localEnv:HOME}/monorepo/packages/types,target=/workspaces/types,type=bind,readonly",

    // Root configs for tooling (read-only)
    "source=${localEnv:HOME}/monorepo/pyproject.toml,target=/workspaces/pyproject.toml,type=bind,readonly",
    "source=${localEnv:HOME}/monorepo/poetry.lock,target=/workspaces/poetry.lock,type=bind,readonly",

    // Cache volumes
    "source=poetry-cache,target=/home/${localEnv:USER}/.cache/pypoetry,type=volume"
  ]
}
```

---

## References

- Dev Container Specification: <https://containers.dev/>
- JSON Reference: <https://containers.dev/implementors/json_reference/>
- Devcontainer CLI: <https://github.com/devcontainers/cli>
- Features Registry: <https://containers.dev/features>
- Debian Packages: <https://packages.debian.org/bookworm/>
- mise Documentation: <https://mise.jdx.dev/>
- rustup Documentation: <https://rust-lang.github.io/rustup/>
