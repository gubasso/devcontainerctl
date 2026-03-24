# Devcontainer Template System

## Purpose

This document formalizes the devcontainer template system used by `dctl init`
and extends it for generic and coordinator-style workflows.

## Current State

The repository ships templates under `templates/`:

- `_base` — internal shared config (not user-selectable)
- `general` — minimal general-purpose config using `devimg/agents:latest`
- `coordinator` — agent/coordinator workflow with parent-directory access
- `python` — Python project config using `devimg/python-dev:latest`
- `rust` — Rust project config using `devimg/rust-dev:latest`
- `zig` — Zig project config using `devimg/zig-dev:latest`

These are installed into `~/.local/share/dctl/templates/` by `make install`.
User-selectable templates contain only project-specific settings. Shared
infrastructure values live in `templates/_base/devcontainer.json` and are
merged with each template at deploy time by `dctl init`.

## Template Categories

The template system supports three categories:

1. **Internal base template**
   - `_base` — shared devcontainer settings (remoteUser, mounts, containerEnv,
     postCreateCommand.dotfiles). Never user-selectable. Underscore prefix
     excludes it from `dctl init --list` and interactive selection.
2. **Language templates**
   - `python`, `rust`, `zig` — language-specific cache mounts and lifecycle
     hooks
3. **Workflow templates**
   - `general` — minimal general-purpose config
   - `coordinator` — agent/coordinator workflow with parent-directory mounts

## Built-In Templates

### `_base` (internal)

Shared infrastructure settings merged into every deployed config:

```json
{
  "remoteUser": "${localEnv:USER}",
  "updateRemoteUserUID": false,
  "init": true,
  "shutdownAction": "none",
  "containerEnv": { ... },
  "mounts": [ /* 17 bind mounts for dotfiles, tools, configs */ ],
  "postCreateCommand": {
    "dotfiles": "${localEnv:DOTFILES}/.devcontainer/setup-dotfiles ${localEnv:DOTFILES}"
  }
}
```

### `general`

```json
{
  "name": "${localWorkspaceFolderBasename}-sandbox",
  "image": "devimg/agents:latest",
  "postCreateCommand": {
    "pre-commit": "pre-commit install"
  }
}
```

### `coordinator`

```json
{
  "name": "${localWorkspaceFolderBasename}-coordinator",
  "image": "devimg/agents:latest",
  "mounts": [
    {
      "source": "${localEnv:HOME}/Projects",
      "target": "${localEnv:HOME}/Projects",
      "type": "bind",
      "readonly": true
    }
  ],
  "postCreateCommand": {
    "pre-commit": "pre-commit install"
  }
}
```

The `coordinator` template uses a parent-area mount to make sibling repositories
visible inside the container. The example path is intentionally simple and should
be treated as a reference default, not as proof that all users store projects in
`~/Projects`.

## User Global Default

The user global default for devcontainer config is:

```text
~/.config/dctl/default/devcontainer.json
```

Purpose:

- Personal fallback when no project-specific config exists
- Reusable default for generic projects or temporary workspaces

Creation model:

- Created manually by the user, or by a future `dctl config init` command
- Not created by `dctl init`

## Three-Tier XDG Layout

### `_base` template owns shared infrastructure settings

The `templates/_base/devcontainer.json` file is the home for:

- `remoteUser`
- `init`
- `shutdownAction`
- `containerEnv`
- shared tool and config mounts
- `postCreateCommand.dotfiles`

### Templates own project-specific settings

Templates should define:

- `name`
- `image`
- language-specific cache mounts
- language-specific `postCreateCommand` entries

Templates must not duplicate settings already owned by `_base`.

### XDG paths

| XDG path | dctl usage | Mutable by |
|----------|-----------|------------|
| `~/.local/share/dctl/templates/` | Installed templates (`make install`) | `make install` only |
| `~/.config/dctl/devcontainer/` | Deployed config (seeded from templates, user-editable) | `dctl init` + user |
| `~/.cache/dctl/devcontainer/` | Generated merged configs | `dctl` (auto-generated) |

- **Data** (`~/.local/share`): installed source templates — lean, modular, scaffolding. `make install` writes here. Used only by `dctl init` to seed config.
- **Config** (`~/.config`): deployed config files — seeded from templates by `dctl init`, then user-editable. Contains separate `_base` and per-template files. This is the user's SoT.
- **Cache** (`~/.cache`): generated merged configs — derived from config files by `dctl init`. Can be deleted and regenerated. `dctl ws up` consumes these.

## Composability

`dctl init` merges `_base` with the selected template at deploy time using
`jq`. The merge produces a standalone `devcontainer.json` in the cache
directory that the Dev Container CLI consumes directly.

Merge semantics:

- Scalars use last-wins behavior (template overrides `_base`).
- Object keys (`containerEnv`, `postCreateCommand`) are merged by key.
- Arrays (`mounts`) are concatenated (`_base` mounts + template mounts).
- JSONC comments are stripped before merging.

The important policy decision is that templates should stay minimal and avoid
re-stating `_base`-owned defaults.

## Template Resolution

Templates resolve from the installed templates directory only (`~/.local/share/dctl/templates/`). User customization happens in the config layer (`~/.config/dctl/devcontainer/`), not in templates.

## Template Discovery

`dctl init` discovers templates from the installed templates directory only:

1. Installed templates: `~/.local/share/dctl/templates/`

Rules:

- Template names map to directory names.
- A valid template directory contains `devcontainer.json`.
- Directories starting with `_` (underscore) are internal and excluded from
  discovery.

## `dctl init` Changes

### `--list`

The `--list` flag prints available templates and exits. Internal templates
(underscore prefix) are excluded.

### Cache target

`dctl init` seeds `_base` and the selected template into `~/.config/dctl/devcontainer/`, then merges those config files and writes the result to:

```text
~/.cache/dctl/devcontainer/<name>/devcontainer.json
```

It then registers that cached path in `~/.config/dctl/projects.yaml`.
`dctl init` does not write `.devcontainer/devcontainer.json`.

Cache freshness is checked via mtime comparison against config files. If the
cache is stale or missing, `dctl init` regenerates it automatically. `--force`
always regenerates regardless of freshness. `dctl ws up` does not regenerate
cache.

## Recommended Template Catalog

- `_base` (internal)
- `general`
- `coordinator`
- `python`
- `rust`
- `zig`

## File Layout

Built-in templates remain in the repository under:

```text
templates/<name>/devcontainer.json
```

Installed templates remain in:

```text
~/.local/share/dctl/templates/<name>/devcontainer.json
```

Deployed config lives in:

```text
~/.config/dctl/devcontainer/<name>/devcontainer.json
```

Generated (cached) configs live in:

```text
~/.cache/dctl/devcontainer/<name>/devcontainer.json
```
