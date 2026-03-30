# Devcontainer Template System

**Status:** Implemented

## Purpose

This document describes the implemented template system used by `dctl init`.

## Template Catalog

Built-in templates in the repository:

- `_00-base` — internal shared config
- `general` — minimal general-purpose sandbox on `devimg/agents:latest`
- `coordinator` — coordinator workflow with parent-area visibility
- `python` — Python project template on `devimg/python-dev:latest`
- `rust` — Rust project template on `devimg/rust-dev:latest`
- `zig` — Zig project template on `devimg/zig-dev:latest`

These install to `~/.local/share/dctl/devcontainers/`.

## Three-Tier XDG Layout

| XDG path | dctl usage | Mutable by |
| --- | --- | --- |
| `~/.local/share/dctl/devcontainers/` | Installed templates | `make install` |
| `~/.config/dctl/devcontainer/` | Seeded config, then user-edited | `dctl init` + user |
| `~/.cache/dctl/devcontainer/` | Generated merged config | `dctl` |

`_00-base` owns the shared infrastructure settings. Selectable templates add the
project-specific image, cache mounts, and lifecycle hooks.

## Merge Semantics

`dctl init` discovers user config layers from `~/.config/dctl/devcontainer/_*/`,
sorts them alphabetically, merges them two-by-two with `jq`, then merges the
selected template last.

- scalar fields use last-wins behavior
- `mounts` are concatenated
- `postCreateCommand` is merged by key
- `containerEnv` is merged by key
- JSONC comments are stripped before merge

## Discovery Rules

- discovery reads installed templates only
- directories beginning with `_` are internal
- `_00-base` is excluded from `dctl init --list`
- merge-time layer discovery reads user config only

## `dctl init` Behavior

`dctl init`:

1. seeds `_00-base` and the selected template into `~/.config/dctl/devcontainer/`
2. discovers all `_*/devcontainer.json` files from user config and merges them with the selected template into `~/.cache/dctl/devcontainer/<name>/devcontainer.json`
3. registers the generated cache path in `~/.config/dctl/projects.yaml`

Cache freshness is based on the config-layer files. `--force` re-seeds config
from installed templates and regenerates cache regardless of mtime.
