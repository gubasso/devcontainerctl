# Devcontainer Templates

Reusable project templates live here for versioned tracking in this repo.

## Three-Tier Flow

```text
devcontainers/  ──make install──>  ~/.local/share/dctl/devcontainers/
                                  │
                                  └──dctl deploy──>  ~/.config/dctl/devcontainer/
                                                             │
                                                             └──merge manifest-declared layers──>  ~/.cache/dctl/devcontainer/
```

- **Installed** (`~/.local/share/dctl/devcontainers/`): built-in templates shipped by `make install`
- **Config** (`~/.config/dctl/devcontainer/`): deployed config files, then user-editable
- **Cache** (`~/.cache/dctl/devcontainer/`): generated merged `devcontainer.json` output consumed by `dctl ws up`

## Installed Files Are Seed Sources Only

Installed files under `~/.local/share/dctl/` are never used directly at runtime.
`dctl deploy devcontainer <name>` copies the manifest and referenced layer files
into user config, and `dctl deploy image <name>` copies the associated managed image
files into user config:

- `~/.config/dctl/devcontainer/` — deployed manifests plus devcontainer.json layers
- `~/.config/dctl/images/` — managed Dockerfile and helper scripts

User config (`~/.config/dctl/`) is the sole runtime source for all operations:
`dctl image build`, `dctl ws up`, `dctl test`. Users can edit these files freely
to customize their setup.

## Template Catalog

### Shipped Layers and Manifests

- `base/devcontainer.json` — shared universal settings (remote user, auth mounts, terminal env)
- `general.yaml`, `coordinator.yaml`, `python.yaml`, `rust.yaml`, `zig.yaml` — selectable manifests

- `general/devcontainer.json` — general-purpose sandbox on `devimg/agents:latest`
- `coordinator/devcontainer.json` — coordinator workflow with a read-only parent-area mount
- `python/devcontainer.json` — Python project config on `devimg/python-dev:latest`
- `rust/devcontainer.json` — Rust project config on `devimg/rust-dev:latest`
- `zig/devcontainer.json` — Zig project config on `devimg/zig-dev:latest`

## Merge Semantics

`dctl init` reads a deployed manifest and merges its listed layers in order
using `jq`.

- `mounts` are concatenated in merge order
- `postCreateCommand` is merged by key
- `containerEnv` is merged by key
- scalar fields use last-wins behavior

## Discovery Rules

- Selectable entries are manifest files (`*.yaml`)
- Manifest-referenced non-leaf layers are treated as managed shared layers during deploy
- The last manifest layer is the user-protected leaf layer
- User customization happens in `~/.config/dctl/devcontainer/`, and those user config files are the only merge inputs
