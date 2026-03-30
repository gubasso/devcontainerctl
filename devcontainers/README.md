# Devcontainer Templates

Reusable project templates live here for versioned tracking in this repo.

## Three-Tier Flow

```text
devcontainers/  ──make install──>  ~/.local/share/dctl/devcontainers/
                                  │
                                  └──seed if missing──>  ~/.config/dctl/devcontainer/
                                                             │
                                                             └──merge _00-base + _NN-* + template──>  ~/.cache/dctl/devcontainer/
```

- **Installed** (`~/.local/share/dctl/devcontainers/`): built-in templates shipped by `make install`
- **Config** (`~/.config/dctl/devcontainer/`): seeded config files, then user-editable
- **Cache** (`~/.cache/dctl/devcontainer/`): generated merged `devcontainer.json` output consumed by `dctl ws up`

## Installed Files Are Seed Sources Only

Installed files under `~/.local/share/dctl/` are never used directly at runtime.
`dctl init` seeds them into user config (`~/.config/dctl/`), which is the sole
runtime source for both devcontainer configs and managed Dockerfiles.

## Template Catalog

### Internal

- `_00-base/devcontainer.json` — shared universal settings (remote user, auth mounts, terminal env). Internal only and never user-selectable.

### Selectable

- `general/devcontainer.json` — general-purpose sandbox on `devimg/agents:latest`
- `coordinator/devcontainer.json` — coordinator workflow with a read-only parent-area mount
- `python/devcontainer.json` — Python project config on `devimg/python-dev:latest`
- `rust/devcontainer.json` — Rust project config on `devimg/rust-dev:latest`
- `zig/devcontainer.json` — Zig project config on `devimg/zig-dev:latest`

## Merge Semantics

`dctl init` merges all user config layers named `_*/devcontainer.json` in alphabetical order, then merges the selected template on top using `jq`.

- `mounts` are concatenated in merge order
- `postCreateCommand` is merged by key
- `containerEnv` is merged by key
- scalar fields use last-wins behavior

## Discovery Rules

- Template discovery reads installed templates only from `~/.local/share/dctl/devcontainers/`
- Directories starting with `_` are internal and excluded from `dctl init --list`
- User customization happens in `~/.config/dctl/devcontainer/`, and those user config files are the only merge inputs
