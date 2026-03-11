# devcontainerctl

Pre-built Docker images and a unified `dctl` CLI for AI-agent devcontainer sandboxes.

## Image Layers

Three-tier architecture on a shared foundation:

| Image | Base | What it adds |
| --- | --- | --- |
| `devimg/agents` | Debian bookworm-slim | Dev tools, Bun, Rust, mise, Node LTS, neovim, Claude Code, Codex, OpenCode, Gemini CLI |
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
- image Dockerfiles to `~/.local/share/dctl/images/`
- devcontainer templates to `~/.local/share/dctl/templates/`

`~/.local/bin` must be in `PATH`. The installer warns if it is missing.

## Setup

```bash
# Build all images (requires dotfiles at ~/.dotfiles or $DOT)
dctl image build --all

# Inspect available images
dctl image list

# Scaffold a project from an installed template
cp "$HOME/.local/share/dctl/templates/python/devcontainer.json" .devcontainer/devcontainer.json
```

## CLI

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
dctl workspace run -- claude  # run via bash -lc
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

## Further Reading

- [QUICKSTART.md](docs/QUICKSTART.md) — Project setup templates and common commands
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — Container/image architecture and troubleshooting
