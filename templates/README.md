# Devcontainer Templates

Reusable project templates live here for versioned tracking in this repo.

## Three-Tier Architecture

Templates follow a three-tier XDG layout:

- **Installed** (`~/.local/share/dctl/templates/`): source templates installed
  by `make install`. Lean, modular scaffolding only. Used by `dctl init` to
  seed config.
- **Config** (`~/.config/dctl/devcontainer/`): deployed config files. Seeded
  from templates by `dctl init`, then user-editable. Contains separate
  `_base/` and per-template files. This is the SoT.
- **Cache** (`~/.cache/dctl/devcontainer/`): generated merged configs from
  config files.

## Templates

### Internal

- `_base/devcontainer.json`: shared infrastructure settings (remoteUser, mounts,
  containerEnv, postCreateCommand.dotfiles). Merged into every deployed config
  at deploy time. Never user-selectable.

### User-Selectable

- `general/devcontainer.json`: minimal general-purpose config using
  `devimg/agents:latest`
- `coordinator/devcontainer.json`: agent/coordinator workflow with
  parent-directory mounts for sibling discovery
- `python/devcontainer.json`: Python project config using
  `devimg/python-dev:latest`
- `rust/devcontainer.json`: Rust project config using `devimg/rust-dev:latest`
- `zig/devcontainer.json`: Zig project config using `devimg/zig-dev:latest`

## How It Works

`dctl init --template <name>` seeds `_base` and the selected template into
`~/.config/dctl/devcontainer/`, then merges those config files using `jq` and
writes the result to `~/.cache/dctl/devcontainer/<name>/devcontainer.json`.
The merged config is registered in `~/.config/dctl/projects.yaml` for runtime
use.

Templates contain only project-specific deltas (name, image, language-specific
mounts, language-specific lifecycle hooks). Shared settings come from `_base`.
