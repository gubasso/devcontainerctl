# Devcontainer Template System

**Status:** Implemented

## Purpose

This document describes the implemented template system used by `dctl init`.

## Template Catalog

Built-in templates in the repository:

- `_base` — internal shared config
- `general` — minimal general-purpose sandbox on `devimg/agents:latest`
- `coordinator` — coordinator workflow with parent-area visibility
- `python` — Python project template on `devimg/python-dev:latest`
- `rust` — Rust project template on `devimg/rust-dev:latest`
- `zig` — Zig project template on `devimg/zig-dev:latest`

These install to `~/.local/share/dctl/templates/`.

## Three-Tier XDG Layout

| XDG path | dctl usage | Mutable by |
| --- | --- | --- |
| `~/.local/share/dctl/templates/` | Installed templates | `make install` |
| `~/.config/dctl/devcontainer/` | Seeded config, then user-edited | `dctl init` + user |
| `~/.cache/dctl/devcontainer/` | Generated merged config | `dctl` |

`_base` owns the shared infrastructure settings. Selectable templates add the
project-specific image, cache mounts, and lifecycle hooks.

## Merge Semantics

`dctl init` merges `_base` and the selected template with `jq`.

- scalar fields use last-wins behavior
- `mounts` are concatenated
- `postCreateCommand` is merged by key
- `containerEnv` is merged by key
- JSONC comments are stripped before merge

## Discovery Rules

- discovery reads installed templates only
- directories beginning with `_` are internal
- `_base` is excluded from `dctl init --list`

## `dctl init` Behavior

`dctl init`:

1. seeds `_base` and the selected template into `~/.config/dctl/devcontainer/`
2. merges them into `~/.cache/dctl/devcontainer/<name>/devcontainer.json`
3. registers the generated cache path in `~/.config/dctl/projects.yaml`

Cache freshness is based on the config-layer files. `--force` re-seeds config
from installed templates and regenerates cache regardless of mtime.
