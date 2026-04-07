# Devcontainer Template System

**Status:** Implemented

## Purpose

This document describes the implemented template system used by `dctl deploy`
and `dctl init`.

## Template Catalog

Built-in templates in the repository:

- `_00-base` — internal shared config
- `general` — minimal general-purpose sandbox on `devimg/agents:latest`
- `coordinator` — coordinator workflow with parent-area visibility
- `python` — Python project template on `devimg/python-dev:latest`
- `rust` — Rust project template on `devimg/rust-dev:latest`
- `zig` — Zig project template on `devimg/zig-dev:latest`

These install to `~/.local/share/dctl/devcontainers/`.

Managed images are a parallel category:

- `agents`
- `python-dev`
- `rust-dev`
- `zig-dev`

## Three-Tier XDG Layout

| XDG path | dctl usage | Mutable by |
| --- | --- | --- |
| `~/.local/share/dctl/devcontainers/` | Installed templates | `make install` |
| `~/.config/dctl/devcontainer/` | Seeded config, then user-edited | `dctl deploy` + user |
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

- `dctl deploy` reads installed templates from `~/.local/share/dctl/devcontainers/`
- `dctl init` reads deployed templates from `~/.config/dctl/devcontainer/`
- directories beginning with `_` are internal
- internal entries are excluded from picker and list output
- merge-time layer discovery reads user config only

## `dctl init` Behavior

`dctl init`:

1. selects a deployed devcontainer from `~/.config/dctl/devcontainer/`
2. discovers all `_*/devcontainer.json` files from user config and merges them
   with the selected devcontainer into
   `~/.cache/dctl/devcontainer/<name>/devcontainer.json`
3. reads the selected devcontainer's `.image`
4. for managed `devimg/<name>:latest` images, validates that the corresponding
   Dockerfile exists in `~/.config/dctl/images/<name>/Dockerfile`
5. for managed images, auto-builds the local image when missing
6. registers the generated cache path in `~/.config/dctl/projects.yaml`
7. runs `dctl test` (the workspace smoke test) against the resolved cache
8. prints a final summary with project, devcontainer, image status, cache and
   registry paths, and the smoke-test result

`dctl init` exits non-zero if the smoke test fails. If no deployed
devcontainers exist, `dctl init` fails and instructs the user to run `dctl
deploy`.

## `dctl deploy` Invariant

`dctl deploy` owns copying installed templates into user config.

- internal `_*/` devcontainer directories are always reconciled on every
  `deploy devcontainer ...` and `deploy --all*` invocation
- internal entries are never listed or user-selectable
- non-internal entries are protected in default mode and only overwritten with
  `--reset`
- internal entries are treated as managed shared infrastructure and are brought
  back into sync even in default mode when they drift

See [`35-deploy.md`](./35-deploy.md) for the full deploy contract.
