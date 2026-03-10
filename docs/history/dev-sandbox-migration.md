# Migration Report: dev-sandbox to devcontainer-images

## Overview

The AI-agent development sandbox was migrated from `dev-sandbox`, a single 814-line bash script managing a systemd-nspawn machine on openSUSE Tumbleweed, to `devcontainer-images`, a Docker/devcontainer-based solution using layered images, the devcontainer CLI spec, and two purpose-built shell tools (`devbox`, `devcontainer-images-build`). The migration preserved all core capabilities (multi-terminal attach, project bind mounts, UID mirroring, config sync) while removing the hard dependency on openSUSE and nspawn, making the sandbox portable to any Linux host with Docker.

---

## Phase 1: dev-sandbox (systemd-nspawn)

### What it was

A single bash script (`bin/.local/bin/dev-sandbox`, 814 lines) that created and managed a long-lived systemd-nspawn machine named `dev-sandbox`. The rootfs lived under `/var/lib/machines/dev-sandbox` and was provisioned from scratch using zypper with openSUSE Tumbleweed repos.

### Architecture

```text
HOST (openSUSE Tumbleweed)
├── /etc/systemd/nspawn/dev-sandbox.nspawn   # Machine config (Boot=yes, VirtualEthernet=no)
├── /var/lib/machines/dev-sandbox/            # Persistent rootfs (zypper-provisioned)
│   ├── .dev-sandbox/initialized             # Sentinel file (provisioning gate)
│   └── workspace/                           # Per-project bind targets
└── /var/lock/dev-sandbox.provision.lock      # flock lock (prevents first-run races)
```

### How it worked

1. **Provisioning** (`provision_rootfs_with_lock`): First run initialized an RPM database in the rootfs, added Tumbleweed repos (oss, non-oss, update, science), imported GPG keys, then installed patterns (`base`, `enhanced_base`, `devel_basis`, `devel_perl`) and a curated package list (fish, git, neovim, fzf, starship, Python, Node.js, Go, Rust, Ruby, Java, Lua, PHP, Perl, and more). A sentinel file was written only on success; failed provisioning retried on next run.

2. **Machine lifecycle** (`ensure_machine_running`): Used `machinectl start/poweroff/terminate` to manage the nspawn machine. Waited for container systemd to respond via `systemd-run -M ... /bin/true` polling (up to 30 retries).

3. **User mirroring** (`ensure_host_user_in_container`): Mirrored the host user's UID/GID/username inside the container by deleting conflicting users/groups and creating the correct user with `useradd -m -u $HOST_UID -U -s /usr/bin/fish`.

4. **Config sync** (`sync_host_config_every_attach`): On every attach, rsynced `~/.config` from host into the container rootfs (`rsync -aL --update`), excluding browser lock files.

5. **Project binding** (`bind_project_with_collision_check`): Dynamically bound host project directories into `/workspace/<basename>` using `machinectl bind`. Detected basename collisions by querying `findmnt` inside the container, with btrfs subvolume normalization.

6. **Attach** (`attach_*`): Interactive shells via `systemd-run -M ... --pty fish`. Three modes: root, host-user (no project), and project (cd into `/workspace/<name>`).

### Key capabilities

| Capability | Implementation |
| --- | --- |
| Multi-terminal attach | Many `systemd-run --pty` sessions into one running nspawn machine |
| Project bind mounts | `machinectl bind` with basename collision detection |
| UID/GID mirroring | Runtime user creation inside container matching host identity |
| Config sync | `rsync -aL --update ~/.config/` on every attach |
| Persistent rootfs | `/var/lib/machines/dev-sandbox/` survived reboots |
| Idempotent provisioning | Sentinel file + flock lock; failed runs retry cleanly |
| Boot at login | `machinectl enable` after first successful provision |
| DNS resolution | `ResolvConf=bind-host` in nspawn config |
| Network | `VirtualEthernet=no` (shared host networking) |
| Kitty integration | Best-effort tab title via `kitten @ set-tab-title` |
| Management CLI | `start`, `stop`, `status`, `setup` subcommands |

### OS coupling

The script was tightly coupled to openSUSE Tumbleweed:

- **Package manager**: zypper (host-side `--root` provisioning into the rootfs)
- **Repos**: Hardcoded Tumbleweed CDN URLs (oss, non-oss, update, science)
- **Container runtime**: systemd-nspawn + machinectl (part of systemd, but the provisioning model assumed zypper)
- **Host prereqs**: `require_cmd zypper`, `require_cmd rpm`, `require_cmd machinectl`, `require_cmd systemd-run`, `require_cmd flock`

---

## Phase 2: Motivation for migration

### OS-agnostic requirement

The dev-sandbox worked well on openSUSE Tumbleweed but could not run on other distributions (e.g., Arch Linux) without porting the zypper-based provisioning. Since the host machine was migrated from openSUSE Tumbleweed to Arch Linux, the nspawn solution had to be replaced with something distribution-independent.

### What had to be preserved

- Isolated, reproducible environment for AI coding agents (Claude Code, Codex, OpenCode)
- Multi-terminal attach to a single running container
- Per-project bind mounts to `/workspaces/<name>`
- Host user identity mirrored inside container (UID/GID matching)
- Host config available inside the container
- Persistent state across sessions (no rebuild on every start)
- No host pollution (packages, runtimes, toolchains stay inside the container)

### What could be dropped

- zypper/RPM dependency (replaced by apt/Debian in Docker images)
- Manual rootfs provisioning (replaced by Dockerfiles)
- Runtime user creation (replaced by build-time UID/GID baking)
- `rsync ~/.config` on every attach (replaced by selective bind mounts)
- Monolithic package list (replaced by layered images with per-project runtime pinning)
- Single-script architecture (replaced by two focused CLI tools + Dockerfiles + systemd units)

---

## Phase 3: devcontainer-images (Docker)

### What replaced it

A stow package (`devcontainer-images`) that deploys:

| Component | Path | Purpose |
| --- | --- | --- |
| Dockerfiles | `~/.devcontainer-images/{agents,python-dev,rust-dev}/` | Layered base images |
| `devcontainer-images-build` | `~/.local/bin/` | Build/rebuild images (interactive fzf or `--all`) |
| `devbox` | `~/.local/bin/` | Project-local devcontainer lifecycle wrapper |
| systemd timer | `~/.config/systemd/user/devcontainer-images-build.timer` | Weekly automated rebuilds (Friday 18:00) |
| systemd service | `~/.config/systemd/user/devcontainer-images-build.service` | Runs `devcontainer-images-build --all` |

### Architecture

```text
Image layers:
  devimg/agents:latest       Debian bookworm-slim + dev tools + AI CLIs + mise + Bun + Node LTS + Rust
       │
       ├── devimg/python-dev:latest   + Poetry (virtualenvs in-project)
       └── devimg/rust-dev:latest     + rustup (--default-toolchain none)

Per-project:
  project/.devcontainer/devcontainer.json
       │
       ├── image: devimg/python-dev:latest
       ├── automatic workspace mount → /workspaces/<project-name>
       ├── mounts → cache volumes, git config, SSH, extra repos
       └── postCreateCommand → mise install && poetry install
```

Runtimes are not baked into images. Python versions come from `pyproject.toml [tool.mise]` and are installed by mise at container creation. Rust toolchains come from `rust-toolchain.toml` and are auto-installed by rustup. Shared Docker volumes cache installed runtimes across projects.

### Key capabilities preserved and new ones gained

**Preserved:**

- Isolated sandbox for AI agents
- Multi-terminal attach (unlimited `devbox shell` / `devbox run` sessions)
- Per-project `/workspaces/<name>` bind mounts (automatic default mount)
- UID/GID matching (baked at image build time via `--build-arg`)
- Host config accessible inside container (selective bind mounts)
- Persistent state (Docker containers persist, cache volumes survive recreations)
- Idempotent start (`devbox up` is a no-op if already running)

**New:**

- OS-agnostic: works on any Linux with Docker (tested on Arch Linux and openSUSE)
- Layered images: shared agent base + thin language extensions
- Per-project runtime pinning: exact Python/Rust versions declared in project files
- Devcontainer spec compliance: standard `devcontainer.json` understood by VS Code, CLI, and other tools
- Cache volumes: mise, Poetry, rustup, and Cargo caches shared across projects
- Read-only reference mounts: mount docs/libraries as read-only alongside the main project
- Rsync snapshots: copy symlink-heavy trees into the container with `-L`
- Docker Compose support: multi-service stacks (app + database + cache)
- Automated weekly rebuilds via systemd user timer
- Devcontainer features: extend images with pre-built feature packages (GitHub CLI, AWS CLI, etc.)
- GPU passthrough: `--gpus=all` for NVIDIA workloads
- Image metadata labels: default devcontainer settings baked into the image, reducing per-project boilerplate

---

## Feature comparison table

| Feature | dev-sandbox (nspawn) | devcontainer-images (Docker) |
| --- | --- | --- |
| **Container runtime** | systemd-nspawn + machinectl | Docker + devcontainer CLI |
| **Base OS** | openSUSE Tumbleweed (zypper provisioned) | Debian bookworm-slim (Dockerfile) |
| **Host OS requirement** | openSUSE Tumbleweed (zypper + nspawn) | Any Linux with Docker |
| **Provisioning method** | zypper `--root` into `/var/lib/machines/` | `docker buildx build` from Dockerfiles |
| **Provisioning gate** | Sentinel file + flock lock | Docker image layers (cached by BuildKit) |
| **Image layering** | Single monolithic rootfs | Three-tier: agents -> python-dev / rust-dev |
| **Multi-terminal** | Multiple `systemd-run --pty` into one machine | Multiple `devbox shell` / `devbox run` into one container |
| **Project bind mounts** | `machinectl bind` (dynamic, with collision detection) | Automatic default mount + `mounts` in `devcontainer.json` (declared) |
| **Basename collision detection** | Runtime `findmnt` check with btrfs normalization | Not needed (mounts declared per-project in config) |
| **UID/GID mirroring** | Runtime `useradd`/`usermod` inside container on every start | Build-time `--build-arg USER_UID/USER_GID` (baked into image) |
| **User conflict resolution** | Destructive: deletes conflicting users/groups at runtime | Not needed (image built for one user) |
| **Config sync** | `rsync -aL --update ~/.config/` on every attach | Selective bind mounts in `devcontainer.json` (e.g., `.gitconfig`, `.ssh/known_hosts`) |
| **Config sync granularity** | All of `~/.config` (with browser lock exclusions) | Per-file/per-directory, read-only or read-write |
| **DNS** | `ResolvConf=bind-host` in nspawn config | Docker default DNS (bridge mode) |
| **Networking** | `VirtualEthernet=no` (host networking) | Docker bridge/NAT (outbound internet) |
| **Init system inside container** | Full systemd boot (`Boot=yes`) | tini via `"init": true` (PID 1 reaping) |
| **Shell** | fish (hardcoded) | bash (default), configurable |
| **Package list** | Monolithic: 35+ packages across 10+ languages | Layered: base dev tools in agents, language tooling in extension layers |
| **Language runtimes** | Baked into rootfs at provision time (all versions) | Pinned per-project via mise/rustup, installed at container creation |
| **Runtime caching** | Rootfs persistence (everything in one rootfs) | Docker volumes (mise-cache, poetry-cache, rustup-toolchains, cargo-registry) |
| **Python** | System python3 + pip + virtualenv + poetry (all in rootfs) | mise-managed version per project + Poetry |
| **Rust** | System rust package (single version) | rustup with per-project `rust-toolchain.toml` |
| **Node.js** | System nodejs + npm | mise-managed Node LTS |
| **AI agent CLIs** | Installed manually inside container | Baked into agents base image (Claude Code, Codex, OpenCode) |
| **Editor** | neovim (from zypper) | neovim (from mise) |
| **Persistence model** | Rootfs under `/var/lib/machines/` survives reboots | Docker container + named volumes survive restarts |
| **Boot-at-login** | `machinectl enable` | Container stays running (`shutdownAction: "none"`) |
| **Rebuild/reprovision** | `dev-sandbox setup` (stops machine, reruns zypper) | `devbox rebuild-images --all` + `devbox reup` |
| **Automated rebuilds** | None | systemd user timer (Friday 18:00, `Persistent=true`) |
| **Image refresh** | Manual `dev-sandbox setup` | `devcontainer-images-build --all` (pulls base updates) |
| **Management CLI** | `dev-sandbox {start,stop,status,setup}` | `devbox {up,reup,shell,exec,run,status,down,rebuild-images}` |
| **Build CLI** | N/A (provisioning embedded in script) | `devcontainer-images-build` (fzf interactive, `--all`, `--dry-run`, `--list`) |
| **Kitty tab title** | `kitten @ set-tab-title` (best-effort) | Not implemented (terminal-agnostic) |
| **Kitty terminfo** | Not explicitly handled (relies on packages in rootfs) | `kitty-terminfo` package in agents image + `TERM` propagation via label |
| **Read-only mounts** | Not supported | `readonly` flag on bind mounts |
| **Multi-directory workspace** | One project per attach session | Multiple directories in `/workspaces` via mounts array |
| **Rsync snapshots** | `~/.config` sync only | General-purpose: any symlink-heavy tree via `postCreateCommand` |
| **Docker Compose** | Not applicable | Supported (multi-service stacks) |
| **GPU support** | Not supported | `--gpus=all` via `runArgs` |
| **Devcontainer features** | Not applicable | Extensible via features registry |
| **Security: sudo** | Root access via `sudo_cmd` / `systemd-run` on host | Container-scoped `NOPASSWD` sudo |
| **Security: mount hygiene** | All of `/workspace` visible; `~/.config` fully synced | Only declared mounts visible; read-only where appropriate |
| **Documentation** | Inline comments in script (57 lines of header) | ARCHITECTURE.md, CLAUDE.md, README.md, QUICKSTART.md |

---

## What improved

1. **OS portability**: No dependency on zypper, RPM, or systemd-nspawn. Works on Arch, Debian, Ubuntu, Fedora — anything with Docker.

2. **Per-project runtime versions**: Instead of one monolithic rootfs with a single Python/Rust/Node version, each project declares its own versions. A Python 3.11 project and a Python 3.12 project coexist without conflict.

3. **Faster reprovisioning**: Rebuilding a Docker image leverages BuildKit layer caching. The old approach ran the full zypper install on every reprovision.

4. **Smaller attack surface per project**: Each project only sees the mounts declared in its `devcontainer.json`. The old solution synced all of `~/.config` on every attach. The new solution mounts only what's needed, with explicit read-only flags.

5. **Declarative over imperative**: Project configuration is a JSON file (`devcontainer.json`) rather than runtime logic in a bash script. Mount composition, environment variables, and post-create commands are all visible in one place.

6. **Separation of concerns**: Image building (`devcontainer-images-build`), project lifecycle (`devbox`), and image definitions (Dockerfiles) are separate components. The old solution was a single 814-line script handling provisioning, lifecycle, user management, config sync, and attach.

7. **Automated maintenance**: A systemd user timer rebuilds all images weekly, pulling base OS updates. The old solution required manual `dev-sandbox setup` runs.

8. **Spec compliance**: The devcontainer spec is understood by VS Code, GitHub Codespaces, and other tools. The old nspawn solution was custom and non-portable.

9. **Multi-directory workspaces**: A single container can mount the main project plus documentation, shared libraries, and reference code — all declared in `devcontainer.json`. The old solution only mounted one project per attach session.

10. **Runtime cache sharing**: Docker volumes for mise, Poetry, rustup, and Cargo are shared across all projects. Installing Python 3.11 for one project makes it instantly available for all others.

---

## Cleanup

To remove dev-sandbox artifacts from the host after migrating:

```bash
# 1. Stop the nspawn machine (if running)
sudo machinectl poweroff dev-sandbox 2>/dev/null || \
sudo machinectl terminate dev-sandbox 2>/dev/null || true

# 2. Disable boot-at-login (removes systemd unit symlink)
sudo machinectl disable dev-sandbox 2>/dev/null || true

# 3. Remove the rootfs (DESTROYS ALL DATA in the sandbox)
sudo rm -rf /var/lib/machines/dev-sandbox

# 4. Remove the nspawn config
sudo rm -f /etc/systemd/nspawn/dev-sandbox.nspawn

# 5. Remove the provisioning lock
sudo rm -f /var/lock/dev-sandbox.provision.lock

# 6. Remove the script itself (deployed via stow)
#    If using dots: dots -D bin
#    Or manually:
rm -f ~/.local/bin/dev-sandbox
```

### Artifacts summary

| Artifact | Path | Owner |
| --- | --- | --- |
| Rootfs | `/var/lib/machines/dev-sandbox/` | root |
| Sentinel | `/var/lib/machines/dev-sandbox/.dev-sandbox/initialized` | root (inside rootfs) |
| Nspawn config | `/etc/systemd/nspawn/dev-sandbox.nspawn` | root |
| Provisioning lock | `/var/lock/dev-sandbox.provision.lock` | root |
| Script | `~/.local/bin/dev-sandbox` | user (stow-managed) |
| Boot-at-login unit | Symlink created by `machinectl enable` (removed by step 2 above) | systemd |
