# CLAUDE.md — devcontainerctl

Pre-built Docker images and the unified `dctl` CLI for AI-agent devcontainer sandboxes.

## Package Layout

After `dots devcontainerctl`:

| Source | Target | Contents |
| --- | --- | --- |
| `.config/dctl/` | `~/.config/dctl/` | Dockerfiles (one subdir per image) |
| `bin/` | `~/.local/bin/` | `dctl` |
| `systemd/` | `~/.config/systemd/user/` | timer + service for weekly rebuilds |

## Image Layers

| Image | Base | Adds |
| --- | --- | --- |
| `devimg/agents` | Debian bookworm-slim | git, ripgrep, fd, eza, fzf, zoxide, starship, Bun, Rust, mise, Node LTS, neovim, Claude Code, Codex, OpenCode |
| `devimg/python-dev` | `devimg/agents` | Poetry + yq/tomlq via mise |
| `devimg/rust-dev` | `devimg/agents` | rustup (`--default-toolchain none`) |
| `devimg/zig-dev` | `devimg/agents` | anyzig + minisign + zig-zls-init |

Runtimes are not baked in; mise and rustup install project-pinned versions at container start.

## CLI

| Command | Purpose | Key options |
| --- | --- | --- |
| `dctl image build` | Build/rebuild base images | `--all`, `--full-rebuild`, `--refresh-agents`, `--dry-run` |
| `dctl image list` | List available image targets | none |
| `dctl workspace ...` | Project-local devcontainer lifecycle | `up`, `reup`, `shell`, `exec`, `run`, `down`, `status` |

`dctl image build` with no image args opens interactive `fzf` selection. `dctl workspace` operates on the current working directory's devcontainer.

## Automation

- **Timer:** `dctl-image-build.timer` — Friday 18:00, `Persistent=true`
- **Service:** Runs `dctl image build --all`
- Enable: `systemctl --user enable --now dctl-image-build.timer`

## Build Args

Images bake the host user's UID/GID at build time:

```bash
USERNAME=$USER USER_UID=$(id -u) USER_GID=$(id -g)
```

The `agents` and `zig-dev` images require the dotfiles repo as a BuildKit named context via `$DOT` (default: `~/.dotfiles`).

## References

- [QUICKSTART.md](QUICKSTART.md) — Project setup templates and common commands
- [ARCHITECTURE.md](ARCHITECTURE.md) — Container/image design rationale and mount patterns
- [DCTL-MIGRATION.md](DCTL-MIGRATION.md) — CLI consolidation plan and mapping
