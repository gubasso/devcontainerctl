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
17. [Implemented Features](#implemented-features)

---

## Overview

### What This Setup Provides

- **Reproducible environments**: Define once, use across all projects of the same type
- **Isolation**: Containers can only access explicitly mounted directories
- **Project-owned dev environments**: Each project pins its toolchain and dependencies in its own files, and its own setup installs them in the container
- **Flexible workspace composition**: Mount multiple directories (repos, docs, libs) into a unified `/workspaces`
- **Multi-agent support**: Attach unlimited terminals/agents to the same container
- **YOLO-safe**: Agents have full permissions inside the container, but limited host access
- **Editor-agnostic**: Edit on host with your native editor; container is a headless execution sandbox

### Reproducibility Philosophy

This guide follows a **project-owned environment** approach:

| Layer | Strategy | Source of Truth |
| ----- | -------- | --------------- |
| Container image | Rolling (rebuild weekly) | The user's Dockerfiles in `~/.config/dctl/images/` |
| Toolchain versions | Pinned per project | The project's own files |
| Dependencies | Pinned per project | The project's own lock files |

dctl ships no image and installs, activates, or names no dev environment manager. The user's image carries the tools that the user's projects need, and each project owns its own dev environment setup, which runs inside the container. A layer can mount a volume that caches installed toolchains across projects, so later containers with the same version start faster.

### Host Runtime Mirroring

For LSP accuracy, give the host the toolchain that the project pins, through the project's own setup.

A project setup may create an environment such as `.venv/` inside the bind-mounted project directory. Since the project directory is shared with the host, the host LSP can discover and use that environment for completions and type-checking.

```bash
# On host (one-time setup per project): install the pinned toolchain
cd ~/projects/my-api

# Start container - project bootstrap can create .venv/ inside the bind mount
devcontainer up --workspace-folder .

# Now host LSP can use the container-created .venv/
nvim .
```

**Why not install the dependencies on the host too?** The `.venv/` is shared via bind mount. Running project bootstrap in both places writes to the same directory, which is redundant. Let the container own the environment; the host just reads it.

### Mental Model

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ HOST                                  CONTAINER                             │
│                                                                             │
│ pinned toolchain for LSP              project bootstrap inside container   │
│   └── from the project's own setup      └── May create .venv/ in project root │
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

## Implemented Features

The design work captured in [`../spec/`](../spec/README.md) is now reflected in
the shipped implementation, not a future roadmap. In particular, the following
are live in the current codebase:

- config resolution with CLI, env, registry, local-file, sibling-discovery, and
  user-default precedence
- per-project registry support in `~/.config/dctl/projects.yaml` for
  `devcontainer-manifest` selection and explicit `sibling_discovery: false`
- YAML manifest-driven layer composition, regenerated fresh on every command
  (never cached) under `$XDG_RUNTIME_DIR/dctl/devcontainer/`
- user config in `~/.config/dctl/` as the only source of manifests, layers,
  and Dockerfiles; dctl ships none, and [`examples/`](examples/README.md)
  shows a starting point
- user-config-only Dockerfile resolution for `dctl image build`, with no
  project-registry coupling
- metadata extraction from the Dockerfile into devcontainer layers
- slim `dctl init` that reads only user config, auto-builds missing
  managed images, registers the project, and runs the smoke test — the merged
  config is regenerated fresh on every command rather than persisted

The spec set remains useful as a design record and glossary:

- [`../spec/README.md`](../spec/README.md) — spec index and glossary
- [`../spec/00-resolution-model.md`](../spec/00-resolution-model.md) — shared precedence and discovery model
- [`../spec/10-project-registry.md`](../spec/10-project-registry.md) — per-project registry design
- [`../spec/20-devcontainer-resolution.md`](../spec/20-devcontainer-resolution.md) — devcontainer resolution flow
- [`../spec/40-dockerfile-hierarchy.md`](../spec/40-dockerfile-hierarchy.md) — Dockerfile override hierarchy
- [`../spec/45-devcontainer-metadata-extraction.md`](../spec/45-devcontainer-metadata-extraction.md) — metadata extraction history

---

## Architecture

### Directory Structure

```text
~/
├── .config/dctl/                  # User config (the user writes it)
│   ├── images/
│   │   └── example/
│   │       └── Dockerfile         # Built as devimg/example:latest
│   ├── devcontainer/
│   │   ├── example.yaml           # Manifest: layer order
│   │   ├── base/
│   │   │   └── devcontainer.json  # Shared layer
│   │   └── example/
│   │       └── devcontainer.json  # Leaf layer
│   └── projects.yaml              # Project registry
│
├── projects/
│   ├── project-a/
│   │   ├── .devcontainer/
│   │   │   └── devcontainer.json
│   │   └── pyproject.toml         # The project pins its own toolchain
│   ├── project-b/
│   │   ├── .devcontainer/
│   │   │   └── devcontainer.json
│   │   └── pyproject.toml
│   └── project-c/
│       ├── .devcontainer/
│       │   └── devcontainer.json
│       └── rust-toolchain.toml
│
└── shared-libs/                   # Libraries mounted as context (RO)
    ├── common-utils/
    └── internal-sdk/
```

### Image Layering Strategy

A user image can start `FROM` another user image, so shared tools build once and child images add what some projects need. The names below are user-defined examples:

```text
devimg/base:latest       (user Dockerfile: distro, user account, agent CLIs)
       │
       ├── devimg/example:latest   (user Dockerfile: FROM devimg/base:latest)
       └── devimg/other:latest     (user Dockerfile: FROM devimg/base:latest)
```

`dctl` infers that tree rather than taking it from the operator. `dctl image build` reads the `FROM` lines of every Dockerfile in the requested ancestor closure and builds each parent before its child. The grammar is literal, because an order the engine cannot read is an order it must not guess:

| `FROM` reference | Meaning |
| --- | --- |
| `devimg/<name>:latest` | managed parent `<name>` |
| `devimg/<name>:v2`, `devimg/<name>` | refused as an unsupported managed-parent spelling |
| any reference holding `$` | refused, because a variable reference cannot be ordered |
| `scratch`, or a stage alias of the same file | not an image reference, ignored |
| anything else | external base, pulled but never ordered |

A `--platform=<platform>` flag and a trailing `AS <alias>` are stripped before the reference is read, and a file may carry several `FROM` lines.

Two build semantics follow from the graph:

- An ordinary build builds every requested name, and builds an ancestor pulled in by the graph only when `docker image inspect` does not already find its tag. A present ancestor prints `skipping <name>: present, not requested`.
- `--full-rebuild` builds every name in the closure with `--no-cache`. Before each build it pulls that Dockerfile's literal external bases by name, once per invocation. It does not pass `--pull` to `docker buildx build`: that flag applies to the whole Dockerfile and would try to resolve a local managed parent such as `devimg/base:latest` against a registry.

A failed build blocks its descendants, which are reported as `blocked by failed parent <name>` rather than built on the older parent tag. Independent branches keep going, and the command fails once with the complete set. `--dry-run` computes the whole order with no Docker daemon, and a cycle or a parent with no Dockerfile is refused there rather than mid-build.

**Note**: dctl ships no image. The same pattern extends to polyglot environments (combine layers) or hardened variants (remove sudo, drop capabilities, add `no-new-privileges`). Write the Dockerfiles for your use case; [`examples/`](examples/README.md) shows one.

### Image Reuse

```text
devimg/example:latest (user image)
       │
       ├── project-a  ─► container (project-a setup installs its toolchain)
       ├── project-b  ─► container (project-b setup installs its toolchain)
       └── project-c  ─► container (project-c setup installs its toolchain)
```

Each project gets its own container with its own environment. The project's own setup installs its pinned toolchain inside each container.

Toolchains installed this way are ephemeral: rebuilding a container downloads them again unless a layer mounts a cache volume for them.

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

dctl ships no image. The user writes one folder per image,
`~/.config/dctl/images/<name>/Dockerfile`, and `dctl image build` tags it
`devimg/<name>:latest`. `make install` installs no Dockerfile. For a starting
point, see [`examples/`](examples/README.md).

### User Naming Convention

The container user is created with the same name as your host `$USER`, and UID/GID are baked in at build time to match the host. This keeps config files (`.gitconfig`, SSH configs, shell rc files) consistent and avoids bind mount permission issues without runtime UID remapping. `dctl image build` passes `--build-arg USERNAME=$USER --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g)` to every build, so a Dockerfile that creates the user reads them as `ARG`s.

### Agent Tools in an Image

The user's image installs the agent CLIs and the tools that the user's projects need. dctl requires none of them.

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
| gh (GitHub CLI) | Official RPM repo | `zypper addrepo` of `https://cli.github.com/packages/rpm/gh-cli.repo` (openSUSE-based image) |
| glab (GitLab CLI) | GitLab releases | Release binary of `https://gitlab.com/gitlab-org/cli` |

**Notes**:

- Claude Code: Native installer recommended (auto-updates); npm still supported
- Codex CLI: Official install is npm; Bun works via npm compatibility (unofficial)
- OpenCode: Installed from the npm package via Bun
- Gemini CLI: Installed globally via npm, so the image needs a Node runtime

**Authentication**:

| Agent | Method |
| ----- | ------ |
| Claude Code | Interactive login (Anthropic subscription) |
| Codex CLI | Interactive login (ChatGPT account) on first run |
| OpenCode | Interactive login (supports multiple providers) |
| Gemini CLI | Interactive login (Google account) or API key |
| gh | `gh auth login` (interactive, GitHub account) |
| glab | `glab auth login` (interactive, GitLab account) |

All listed CLIs authenticate interactively on first run. For `gh` and `glab`, dctl seeds an ephemeral copy of the host config — tokens included — and mounts it into containers at up/exec time (see below). Other CLIs persist auth via config directory mounts (see [Pattern 6](#pattern-6-config-with-selective-rw-mounts)).

#### GitHub CLI (gh) and GitLab CLI (glab) Setup

When the user's image installs both CLIs, they require one-time host authentication before they work inside containers. The host config directories (`~/.config/gh`, `~/.config/glab-cli`) are never mounted: they hold long-lived credentials (gh refresh material, keyring markers), so containers only ever see a seeded, ephemeral copy.

**Prerequisites (host)**:

```bash
# Verify the CLIs are available on the host
gh --version
glab --version
```

If missing, install them on the host first:

```bash
# gh — https://cli.github.com/
# glab — https://gitlab.com/gitlab-org/cli
```

**One-time authentication (host)**:

```bash
# GitHub CLI — creates ~/.config/gh/hosts.yml with your OAuth token
gh auth login

# GitLab CLI — stores your token in the system keyring
glab auth login
```

Both commands are interactive and guide you through protocol selection (SSH or HTTPS) and token creation. Choose SSH as the git protocol if you want git push/pull to use your existing SSH keys.

**How it works in containers**:

Modern `gh` (v2.24.0+) and `glab` store tokens in the system keyring, which is inaccessible from containers. So on every `up` and `exec`, dctl invokes the host tool `forge-seed` (user-provided; the contract is specified in [docs/specs/secret-forwarding/SPEC.md](./specs/secret-forwarding/SPEC.md)), which writes a per-project copy of the gh/glab config under `$XDG_RUNTIME_DIR/forge-auth/<project>` (tmpfs-backed, `0700`/`0600`), injecting the tokens the host CLIs read from the keyring; dctl bind-mounts that dir into the container at `/run/forge-auth`. The container reaches it through `GH_CONFIG_DIR`/`GLAB_CONFIG_DIR` — **no token ever enters the container environment**. Because the seed dir is a live bind, re-seeding at exec time updates what an already-running container sees.

| Component | What happens |
| --------- | ------------ |
| API calls (`gh pr create`, `glab mr list`) | Read the seeded config via `GH_CONFIG_DIR` / `GLAB_CONFIG_DIR` |
| Git transport (`git push/pull`) | Uses the forwarded SSH agent socket at `/run/dctl/ssh-agent.sock` (if remotes are `git@...`) or the CLI credential helper (if remotes are `https://...`) |

**Verification (inside container)**:

```bash
# Check authentication status
gh auth status
glab auth status

# Verify API access
gh api user --jq .login
glab api user --jq .username
```

**Sensitive files** (do not commit to version control):

| CLI | File | Contains |
| --- | ---- | -------- |
| gh | `~/.config/gh/hosts.yml` | OAuth token (plain text fallback when no system keyring) |
| glab | `~/.config/glab-cli/config.yml` | Auth state per host; tokens live in the system keyring (`use_keyring`), with a plain-text `token:` field only as the keyringless fallback |
| both | `$XDG_RUNTIME_DIR/forge-auth/<project>/` | Seeded copies carrying live tokens — tmpfs-backed, cleared at logout, readable inside the container at `/run/forge-auth` |

#### Neovim

dctl adds no editor configuration. When the image installs Neovim, its full configuration can come through an optional user layer such as `dotfiles`.

### Build Base Images

Use the provided `dctl image` commands:

```bash
# Interactive selection (fzf)
dctl image build

# Build a specific image
dctl image build example

# Build all images (non-interactive)
dctl image build --all

# Full uncached rebuild of all images
dctl image build --full-rebuild

# Preview what would be built
dctl image build --dry-run
```

Or build manually:

```bash
cd ~/.config/dctl/images
docker buildx build --load --build-arg USERNAME=$USER --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) -t devimg/example:latest ./example/
```

---

## Runtime Version Management

### Philosophy

dctl installs, activates, and names no runtime or dev environment manager. Each project owns its own dev environment setup: it pins its toolchain and dependencies in its own files, and its own setup installs them inside the container, for example from a `postCreateCommand` in the leaf layer. The user makes sure that the image carries what that setup needs.

This keeps the shared image layer reusable while giving each project exact version control. The same project files work for CI and other developers without containers.

### What's Shared vs Isolated

| Component | Scope | Storage |
| --------- | ----- | ------- |
| Project toolchains | Per-container | Installed by the project's own setup |
| Toolchain caches | User-scoped volume, when a layer mounts one | For example `cargo-registry-<user>` (see [Pattern 1](#pattern-1-user-scoped-cache-volumes-rust)) |
| Package manager caches | Per-container (ephemeral) | `~/.cache/` (no volume) |
| Project environments | Per-project | For example `.venv/` in project dir (created by container, read by host LSP) |
| Build output | Per-project | For example `target/` in project dir |

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

Shared auth mounts and baseline container settings come from the `base`
layer, merged by `dctl init` via the YAML manifest. Each selectable config is
defined by a manifest that declares its layer composition:

```yaml
# ~/.config/dctl/devcontainer/example.yaml — user manifest
layers:
  - base      # shared layer: remote user, auth mounts, terminal env
  - agents    # shared layer: bubblewrap-friendly seccomp profile, agent CLI mounts
  - example   # leaf layer: image tag, cache volumes, bootstrap commands
```

The last layer is the **leaf**, the layer of this one devcontainer; preceding
layers are **shared** with other manifests. The user writes every manifest and
layer; [`examples/`](examples/README.md) shows a set. Manifests are validated
against `schemas/compose.schema.yaml`.

The examples below show only project-local deltas (the leaf layer content).

### Standard Leaf Configuration

```jsonc
// project-a/.devcontainer/devcontainer.json
{
  "name": "${localWorkspaceFolderBasename}-sandbox",
  "image": "devimg/example:latest",
  "postCreateCommand": {
    // the project's own setup command
    "setup": "make setup"
  }
}
```

### With Cache Volumes

```jsonc
{
  "name": "${localWorkspaceFolderBasename}-sandbox",
  "image": "devimg/example:latest",
  "mounts": [
    // rust toolchain + registry (user-scoped volumes to avoid ownership conflicts)
    {
      "source": "rustup-toolchains-${localEnv:USER}",
      "target": "${localEnv:HOME}/.rustup",
      "type": "volume"
    },
    {
      "source": "cargo-registry-${localEnv:USER}",
      "target": "${localEnv:HOME}/.cargo/registry",
      "type": "volume"
    },
    {
      "source": "cargo-git-${localEnv:USER}",
      "target": "${localEnv:HOME}/.cargo/git",
      "type": "volume"
    }
  ],
  "postCreateCommand": {
    "rust": "cargo build"
  }
}
```

### With Git/SSH Config

```jsonc
{
  "name": "project-a",
  "image": "devimg/example:latest",

  "mounts": [
    "source=${localEnv:HOME}/.ssh/known_hosts,target=/home/${localEnv:USER}/.ssh/known_hosts,type=bind,readonly"
  ]
}
```

### With Additional Project Mounts

The automatic workspace mount handles the main project (mounted to
`/workspaces/<basename>`). Use `mounts` to place additional repositories
alongside it.

```jsonc
{
  "name": "project-a",
  "image": "devimg/example:latest",

  "mounts": [
    "source=${localEnv:HOME}/projects/shared-lib,target=/workspaces/shared-lib,type=bind,readonly"
  ]
}
```

### Base Configuration Reuse via the `base` Layer

Shared devcontainer defaults live in a `base` layer that the user writes at `~/.config/dctl/devcontainer/base/devcontainer.json`; [`examples/`](examples/README.md) shows one. dctl reads every layer from `~/.config/dctl/devcontainer/` and never copies or overwrites one. The layers declared in the YAML manifest are merged in the declared order on demand — regenerated fresh on every `dctl ws up`/`reup`/`test` (and by `dctl init`'s smoke test), never cached — so edits to any layer apply immediately.

**Defaults that a `base` layer typically sets:**

| Property | Value | Notes |
| -------- | ----- | ----- |
| `remoteUser` | `${localEnv:USER}` | Matches host username |
| `updateRemoteUserUID` | `false` | UID/GID baked at build time |
| `init` | `true` | Proper init process (PID 1 reaping) |
| `shutdownAction` | `"none"` | Container keeps running after detach |
| `containerEnv` | `TERM`, `COLORTERM` | Propagates host terminal defaults |
| `mounts` | gitconfig, gh, glab-cli, Claude, /tmp | Universal shared mounts |

**Merge rules** (applied by `dctl init`):

- `mounts` arrays are concatenated in layer order
- `postCreateCommand`, `containerEnv`, and `remoteEnv` objects are merged by key (later layer wins)
- scalar fields use last-wins (later layers override earlier ones)

### Creating a Custom Manifest

To compose a custom layer stack (e.g. adding a dotfiles layer), create a
manifest in user config:

```yaml
# ~/.config/dctl/devcontainer/myproject.yaml
name: myproject
layers:
  - base
  - agents      # include if you want your seccomp profile + agent mounts
  - dotfiles    # personal layer
  - myproject   # leaf — last layer
```

Add each layer directory with a `devcontainer.json`, for example
`~/.config/dctl/devcontainer/dotfiles/devcontainer.json`, then run
`dctl init --devcontainer myproject`.

After editing `base`, a custom layer, or a manifest, just recreate the container — the merged config is regenerated fresh on `ws reup`, so no `dctl init` re-run is needed:

```bash
dctl ws reup
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

#### Pattern 1: User-Scoped Cache Volumes (Rust)

Rust toolchains and registry downloads are large and slow to rebuild. Use
user-scoped named volumes so each host user gets a separate volume, avoiding
ownership conflicts when multiple users share the same Docker daemon:

```jsonc
{
  "mounts": [
    "source=rustup-toolchains-${localEnv:USER},target=/home/${localEnv:USER}/.rustup,type=volume",
    "source=cargo-registry-${localEnv:USER},target=/home/${localEnv:USER}/.cargo/registry,type=volume",
    "source=cargo-git-${localEnv:USER},target=/home/${localEnv:USER}/.cargo/git,type=volume"
  ]
}
```

#### Pattern 2: Ephemeral Caches (Python, Zig)

Package manager caches that are small and fast to rebuild (for example pip or Zig)
should **not** use volumes. Let each container manage its own ephemeral cache
under `~/.cache/`. This avoids permission mismatches, concurrent-write
corruption, and debugging overhead that outweighs the download-time savings.

#### Cache Volume Hygiene

Wipe user-scoped Rust volumes when corruption is suspected:

```bash
docker volume rm rustup-toolchains-${USER} cargo-registry-${USER} cargo-git-${USER} 2>/dev/null || true
```

#### Pattern 3: Project + Shared Libraries (RO)

```jsonc
{
  "mounts": [
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

Use `dctl ws` for normal lifecycle operations. Raw `devcontainer` and `docker` commands remain available when needed.

### Start Container

```bash
cd ~/projects/project-a
dctl ws up
```

### Find Container(s)

```bash
cd ~/projects/project-a
dctl ws status
```

### Attach Multiple Agents

```bash
cd ~/projects/project-a

# Multiple agent sessions
dctl ws shell claude
dctl ws shell codex

# Interactive shell
dctl ws shell
```

### Stop/Remove Container(s)

```bash
cd ~/projects/project-a
dctl ws down
```

### Compose Projects

```bash
docker compose -f .devcontainer/docker-compose.yml down
```

---

## Security Model

### Default Security Profile

- dctl ships no image and no layer, so the sudo policy and any seccomp profile come from the user's image and layers
- A sudo rule narrowed to one command, such as `/usr/bin/zypper`, removes the common `sudo <arbitrary command>` path, but `sudo zypper install /local.rpm` will still run that RPM's `%post` script as root, so it is a defense-in-depth narrowing rather than a hard root-execution boundary
- A layer can pass a seccomp profile through `runArgs`; the `agents` layer of [`examples/`](examples/README.md) carries `seccomp-bwrap.json`
- Safety comes from **mount hygiene**

```jsonc
{
  "image": "devimg/example:latest",

  "privileged": false,

  "mounts": []
}
```

**Protects against**:

- Reading host files you did not mount
- Docker daemon control (if you don't mount docker.sock)

**Does NOT protect against**:

- Exfiltration of any readable mounted secret over the network
- Root inside the container reading all mounted secrets

**Hardening**: restrict sudo in your image, and pass a seccomp profile that blocks the highest-risk container-escape / kernel-LPE syscalls from a layer. For higher security, use moby's default-deny baseline as the profile for moby's default-deny baseline (see https://github.com/moby/profiles), drop all capabilities via --cap-drop=ALL, and add no-new-privileges in your leaf layer.

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

See [README.md](../README.md) and [QUICKSTART.md](QUICKSTART.md) for the
baseline install/init/up/shell flow. The key `dctl`-specific workflow behavior
to keep in mind is:

- the user writes manifests, layers, and Dockerfiles into `~/.config/dctl/`;
  dctl ships none, and [`examples/`](examples/README.md) shows a starting point
- `dctl init` selects a manifest from `~/.config/dctl/devcontainer/`,
  registers the project, auto-builds the managed image, and runs the smoke test
- `dctl ws up` and `dctl ws reup` resolve config through the six-level
  precedence chain — for a registered project this regenerates the merged config
  fresh from the manifest layers under
  `$XDG_RUNTIME_DIR/dctl/devcontainer/<name>/devcontainer.json` (never cached) —
  before invoking the Dev Container CLI (manifest-backed projects require `jq`)
- `dctl ws shell`, `exec`, and `run` attach to containers by workspace label and
  forward auth plus terminal environment
- `dctl ws reup` is the right move after changing managed images or a config
  layer; it regenerates the merged config and recreates the container, so no
  `dctl init` re-run is needed

Common lifecycle commands:

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

---

## Image Refresh Workflow

### Weekly Refresh (Recommended)

```bash
dctl image build --all
```

`dctl image build --all` builds every image under `~/.config/dctl/images/`, parents first. `dctl image build --full-rebuild` also pulls the external bases and builds with no cache.

### Update Running Projects

```bash
cd ~/projects/project-a
dctl ws reup
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
FROM devimg/example:latest

USER root
RUN zypper --non-interactive install --no-recommends \
        Mesa-libGL1 \
    && zypper clean --all
USER $USERNAME
```

### Docker Compose for Multi-Container

**Note**: Docker Compose mode does not get any extra `dctl` wrapper behavior by
itself. If you bypass the normal manifest-driven layer composition flow, set the required
shared mounts, env, lifecycle hooks, and user settings explicitly in the
compose-based config.

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
    image: devimg/example:latest
    volumes:
      - ..:/workspaces/<project-name>
      - ~/.gitconfig:/home/${USER}/.gitconfig:ro
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
```

### Features (Pre-built Extensions)

```jsonc
{
  "name": "project",
  "image": "devimg/example:latest",

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
  "image": "devimg/example:latest",

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

UID/GID should match if the image was built with the correct `USER_UID`/`USER_GID` build args. Rebuild with `dctl image build --all` if they don't match.

### Cache Volume Permission Issues

If caches were created with a different UID/GID:

```bash
docker volume rm rustup-toolchains-${USER} cargo-registry-${USER} cargo-git-${USER} 2>/dev/null || true
```

### Project Setup Fails

The project's own setup runs inside the container. Run it by hand to see the error, and check that the image carries the tools that it needs:

```bash
dctl ws run -- make setup
```

### SSH Key Permission Denied

```bash
chmod 600 ~/.ssh/deploy_key
```

### Agent Can't Connect to API

```bash
# Check network connectivity
devcontainer exec --workspace-folder . curl -I https://api.anthropic.com

# Re-run the agent command if needed
devcontainer exec --workspace-folder . bash -lic "claude"
```

### gh or glab Not Authenticated in Container

```bash
# Check if config directories exist on the host
ls ~/.config/gh/hosts.yml
ls ~/.config/glab-cli/config.yml

# If missing, authenticate on the host first
gh auth login
glab auth login

# Then recreate the container to pick up the mounted config
dctl ws reup
```

If the config files exist but the CLI still reports unauthenticated, check that the bind mount is active:

```bash
# Inside container
mount | grep -E 'gh|glab-cli'
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

# Remove user-scoped cache volumes
docker volume rm rustup-toolchains-${USER} cargo-registry-${USER} cargo-git-${USER} 2>/dev/null || true

# Prune dangling volumes
docker volume prune

# Rebuild from scratch (pulls the external bases, builds with no cache)
dctl image build --full-rebuild
```

---

## Quick Reference

### Commands

```bash
# Start container
dctl ws up

# Recreate container
dctl ws reup

# Attach shell
dctl ws shell

# Execute command: each word is one argument; name a shell for an expression
dctl ws run -- pytest -q
dctl ws run -- bash -c 'a && b'

# Show container details
dctl ws status

# Stop/remove container
dctl ws down

# Rebuild images
dctl image build --all
```

### Files

| File | Purpose |
| ---- | ------- |
| `~/.config/dctl/images/*/Dockerfile` | User-written Dockerfile definitions |
| `~/.config/dctl/devcontainer/*.yaml` | User-written manifests |
| `project/.devcontainer/devcontainer.json` | Per-project container config |

### Key devcontainer.json Fields

| Field | Purpose |
| ----- | ------- |
| `image` | Base image to use |
| `workspaceFolder` | Working directory inside container (only needed in Docker Compose mode) |
| `mounts` | Additional bind mounts and volumes |
| `containerEnv` | Environment variables |
| `postCreateCommand` | Run once after container creation |
| `remoteUser` | User to run as (from `base` layer) |
| `updateRemoteUserUID` | Map container UID to host UID (from `base` layer) |
| `init` | Use proper init process (from `base` layer) |
| `shutdownAction` | What to do when closed (from `base` layer) |

### Volume Reference

These volumes exist only when a layer mounts them:

| Volume | Contents | Scope |
| ------ | -------- | ----- |
| `rustup-toolchains-<user>` | Rust toolchains | User-scoped |
| `cargo-registry-<user>` | Crates.io index + crates | User-scoped |
| `cargo-git-<user>` | Git-based dependencies | User-scoped |

Other package manager caches are ephemeral (no volume). Each container
creates its own cache under `~/.cache/` on first use.

### Mount Types

| Type | Syntax | Use Case |
| ---- | ------ | -------- |
| Bind (rw) | `source=...,target=...,type=bind` | Main working repo |
| Bind (ro) | `source=...,target=...,type=bind,readonly` | Reference docs/libs |
| Rsync | `postCreateCommand: rsync -aL ...` | Symlink-heavy sources |
| Volume | `source=name,target=...,type=volume` | Caches, toolchains |

---

## Full Configuration Examples

Complete `devcontainer.json` examples demonstrating multi-directory workspaces.
Each project uses the default automatic workspace mount for the main repository.
These rely on the shared defaults from the `base` layer. For an example image
and layers, see [`examples/`](examples/README.md).

### Example 1: API Project with Docs and SDK

Open from the `my-api` project directory.

```jsonc
{
  "name": "my-api-workspace",
  "image": "devimg/example:latest",

  "mounts": [
    // Documentation (read-only context)
    "source=${localEnv:HOME}/projects/my-api-docs,target=/workspaces/docs,type=bind,readonly",

    // Internal SDK (read-only context)
    "source=${localEnv:HOME}/libs/internal-sdk,target=/workspaces/internal-sdk,type=bind,readonly",

  ]
}
```

### Example 2: Workspace with Rsync Snapshot

Open from the `my-api` project directory. The rsync snapshot copies a
symlink-heavy SDK into a flat directory at container creation time.

```jsonc
{
  "name": "my-api-workspace",
  "image": "devimg/example:latest",

  "mounts": [
    // Source for rsync (temporary mount point)
    "source=${localEnv:HOME}/libs/legacy-sdk,target=/mnt/src-legacy-sdk,type=bind,readonly"
  ],

  // Snapshot legacy-sdk into /workspaces (resolves symlinks)
  "postCreateCommand": {
    "rsync-sdk": "rsync -aL --delete /mnt/src-legacy-sdk/ /workspaces/legacy-sdk/"
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
  "image": "devimg/example:latest",

  "mounts": [
    // Only the packages you're working on (read/write)
    "source=${localEnv:HOME}/monorepo/packages/auth,target=/workspaces/auth,type=bind",
    "source=${localEnv:HOME}/monorepo/packages/api,target=/workspaces/api,type=bind",

    // Shared types (read-only)
    "source=${localEnv:HOME}/monorepo/packages/types,target=/workspaces/types,type=bind,readonly",

    // Root configs for tooling (read-only)
    "source=${localEnv:HOME}/monorepo/pyproject.toml,target=/workspaces/pyproject.toml,type=bind,readonly"
  ]
}
```

---

## References

- Dev Container Specification: <https://containers.dev/>
- JSON Reference: <https://containers.dev/implementors/json_reference/>
- Devcontainer CLI: <https://github.com/devcontainers/cli>
- Features Registry: <https://containers.dev/features>
- openSUSE Packages: <https://software.opensuse.org/>
