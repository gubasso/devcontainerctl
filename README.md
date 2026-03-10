# devcontainerctl

Pre-built Docker images and a unified `dctl` CLI for AI-agent devcontainer sandboxes.

## Image Layers

Three-tier architecture on a shared foundation:

| Image | Base | What it adds |
| --- | --- | --- |
| `devimg/agents` | Debian bookworm-slim | Dev tools, Bun, Rust, mise, Node LTS, neovim, Claude Code, Codex, OpenCode |
| `devimg/python-dev` | `devimg/agents` | Poetry via mise (`virtualenvs.in-project = true`) |
| `devimg/rust-dev` | `devimg/agents` | rustup (`--default-toolchain none`) |
| `devimg/zig-dev` | `devimg/agents` | anyzig + minisign + zig-zls-init |

Images provide tooling, not language runtime versions. Project runtime versions stay pinned in project config and are installed at container start.

## Setup

```bash
# Deploy package (symlinks Dockerfiles, dctl, and systemd units)
dots devcontainerctl

# Build all images (requires dotfiles at ~/.dotfiles or $DOT)
dctl image build --all

# Enable weekly rebuild timer (Friday 18:00)
systemctl --user enable --now dctl-image-build.timer
```

Image definitions now live under `~/.config/dctl/` following the XDG Base Directory spec.

## CLI

### `dctl image`

```bash
dctl image build                  # interactive fzf selection
dctl image build agents           # specific image
dctl image build --all            # all images (pulls base updates)
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

## Further Reading

- [DCTL-MIGRATION.md](docs/DCTL-MIGRATION.md) — CLI migration and architecture spec
- [QUICKSTART.md](docs/QUICKSTART.md) — Project setup templates and common commands
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — Container/image architecture and troubleshooting
