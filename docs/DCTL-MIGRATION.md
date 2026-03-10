# Dctl Migration Architecture

## Overview

This project is consolidating `devbox` and `devcontainer-images-build` into a single `dctl` command so workspace lifecycle and image management share one CLI surface, one code path, and one place for future extensions. This builds on the container/image work documented in [history/dev-sandbox-migration.md](history/dev-sandbox-migration.md) and also standardizes user-facing paths on the XDG Base Directory spec.

## Command Mapping

| Old | New |
| --- | --- |
| `devbox up [-- <args>]` | `dctl workspace up [-- <args>]` |
| `devbox reup [-- <args>]` | `dctl workspace reup [-- <args>]` |
| `devbox exec [-- <cmd>]` | `dctl workspace exec [-- <cmd>]` |
| `devbox shell [<cmd>]` | `dctl workspace shell [<cmd>]` |
| `devbox run [--] <cmd>` | `dctl workspace run [--] <cmd>` |
| `devbox status` | `dctl workspace status` |
| `devbox down` | `dctl workspace down` |
| `devbox rebuild-images [-- <args>]` | `dctl image build [-- <args>]` |
| `devbox help` | `dctl help` or `dctl workspace help` |
| `devcontainer-images-build` | `dctl image build` |
| `devcontainer-images-build <image>` | `dctl image build <image>` |
| `devcontainer-images-build --all` | `dctl image build --all` |
| `devcontainer-images-build --full-rebuild` | `dctl image build --full-rebuild` |
| `devcontainer-images-build --refresh-agents` | `dctl image build --refresh-agents` |
| `devcontainer-images-build --dry-run` | `dctl image build --dry-run` |
| `devcontainer-images-build --list` | `dctl image list` |

Key decisions:

- `--refresh-agents`, `--full-rebuild`, `--all`, and `--dry-run` remain flags on `dctl image build`.
- `--list` becomes the separate `dctl image list` action.
- Legacy commands are removed instead of kept as shims.

## Target CLI Tree

```text
dctl
├── workspace
│   ├── up
│   ├── reup
│   ├── exec
│   ├── shell
│   ├── run
│   ├── status
│   ├── down
│   └── help
├── image
│   ├── build
│   ├── list
│   └── help
├── help
└── version
```

## XDG Paths

All user-facing paths follow the XDG Base Directory specification:

| Variable | Default | `dctl` usage |
| --- | --- | --- |
| `XDG_CONFIG_HOME` | `~/.config` | `~/.config/dctl/` for image definitions and future config |
| `XDG_CACHE_HOME` | `~/.cache` | `~/.cache/dctl/` reserved for future cache use |
| `XDG_DATA_HOME` | `~/.local/share` | `~/.local/share/dctl/` reserved for future state/data |

Image definitions layout:

```text
~/.config/dctl/
├── agents/
│   └── Dockerfile
├── python-dev/
│   └── Dockerfile
├── rust-dev/
│   └── Dockerfile
└── zig-dev/
    └── Dockerfile
```

In code:

```bash
IMAGES_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dctl"
```

Systemd units use `ConditionPathExists=%h/.config/dctl`.

## Code Architecture

- `bin/dctl` is the single CLI entrypoint.
- The merged script stays single-file for now; current scope does not justify a `lib/` split.
- `set -euo pipefail` is required; no global `IFS` override is used.
- Function naming stays simple and prefixed by area, for example `cmd_workspace_up` and `cmd_image_build`.
- Dispatch is two-level: `$1` selects `workspace` or `image`, then `$2` selects the command.
- The `# --- Main` marker is preserved so Bats tests can source helpers without invoking the CLI.

## File Changes

| File | Action | Notes |
| --- | --- | --- |
| `bin/devbox` | delete | absorbed into `bin/dctl` |
| `bin/devcontainer-images-build` | delete | absorbed into `bin/dctl` |
| `bin/dctl` | create | merged CLI with XDG-aware `IMAGES_DIR` |
| `images/` | move | replaced by `.config/dctl/` for stow deployment |
| `systemd/devcontainer-images-build.service` | rename | now `systemd/dctl-image-build.service` |
| `systemd/devcontainer-images-build.timer` | rename | now `systemd/dctl-image-build.timer` |
| `hooks/post-stow` | edit | new commands, new timer name, new XDG path |
| `tests/devbox_test.bats` | rename | now `tests/dctl_test.bats` |
| `README.md` | edit | `dctl` becomes the only public CLI |
| `docs/CLAUDE.md` | edit | package layout and examples updated |
| `docs/QUICKSTART.md` | edit | `dctl workspace` and `dctl image` examples |
| `docs/ARCHITECTURE.md` | edit | command and path references updated; container architecture remains separate |

## Stow Deployment

| Source | Target | Notes |
| --- | --- | --- |
| `bin/dctl` | `~/.local/bin/dctl` | single binary |
| `.config/dctl/*` | `~/.config/dctl/*` | image definitions |
| `systemd/dctl-image-build.*` | `~/.config/systemd/user/dctl-image-build.*` | renamed units |

Migration procedure for existing users:

```bash
systemctl --user disable --now devcontainer-images-build.timer
dots devcontainerctl
systemctl --user daemon-reload
systemctl --user enable --now dctl-image-build.timer
rmdir ~/.devcontainer-images 2>/dev/null || true
```

## Behavior Preservation

These behaviors must not change during consolidation:

- Workspace-scoped container discovery still uses the `devcontainer.local_folder` label.
- `exec`, `shell`, and `run` auto-start a missing container; `status` and `down` do not.
- Terminal env forwarding still passes `TERM`, `COLORTERM`, `TERM_PROGRAM`, and `TERM_PROGRAM_VERSION`.
- `dctl image build` still supports interactive `fzf` selection when no image target is provided.
- Image builds still reject root, still honor `DOT`, and still require the named dotfiles context for `agents` and `zig-dev`.
- Passthrough handling after `--` remains supported where it exists today.
