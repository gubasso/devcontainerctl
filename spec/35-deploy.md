# Deploy Managed Assets

**Status:** Implemented

## Purpose

This document defines `dctl deploy`, the command that copies installed managed
assets from `~/.local/share/dctl/` into `~/.config/dctl/`.

Installed files are seed sources only. If a file is not present in user config,
it cannot be used at runtime.

## CLI Surface

```text
dctl deploy devcontainer <name> [--reset|--dry-run]
dctl deploy image <name>        [--reset|--dry-run]
dctl deploy --all               [--reset|--dry-run]
dctl deploy --all-devcontainers [--reset|--dry-run]
dctl deploy --all-images        [--reset|--dry-run]
dctl deploy
dctl deploy --list
dctl deploy --list-devcontainers
dctl deploy --list-images
dctl deploy --help
```

`dctl deploy` with no positional selector starts an interactive picker.

## Categories

- `devcontainer`: copies the installed manifest (`<name>.yaml`) and its
  referenced layer directories from `~/.local/share/dctl/devcontainers/`
  into `~/.config/dctl/devcontainer/`
- `image`: copies installed image files from
  `~/.local/share/dctl/images/<name>/` into `~/.config/dctl/images/<name>/`

The deploy walker operates recursively and preserves relative paths.

## Modes

Exactly one of these modes applies:

1. `--dry-run`
2. default
3. `--reset`

`--dry-run` and `--reset` are mutually exclusive.

### `--dry-run`

- prints the per-file plan
- writes nothing

### Default mode

- creates missing target files
- skips existing leaf-layer files
- for managed manifest files and non-leaf devcontainer layers, reconciles drift back to the installed copy

### `--reset`

- for each shipped file:
  - if missing: creates it
  - if identical: no-op
  - if different: backs up the existing file and overwrites it

Backups are created per-file only. User-only files that do not exist in the
installed source tree are never touched.

## Backup Format

Backups are named:

```text
<original-filename>.bak.<UTC-ISO-DATE>
```

The timestamp format is:

```text
date -u '+%Y-%m-%dT%H-%M-%SZ'
```

Example:

```text
devcontainer.json.bak.2026-04-07T12-34-56Z
```

## Managed Manifest Invariant

A manifest declares layers in order; the **last** layer is the **leaf**
(user-protected), all preceding layers are **shared** (managed infrastructure).
Example:

```yaml
# rust.yaml
layers:
  - base    # shared — reconciled on every deploy
  - agents  # shared — reconciled on every deploy
  - rust    # leaf — created once, then skip-if-exists
```

Any installed devcontainer manifest (`*.yaml`) is selectable and always managed.
For each selected manifest:

- the manifest file itself is always processed on every
  `dctl deploy devcontainer ...`
- all non-leaf manifest layers are always processed on every
  `dctl deploy devcontainer ...`
- the same rules apply to `dctl deploy --all` and `dctl deploy --all-devcontainers`
- only manifest names are listed or shown in pickers
- manifest files and non-leaf layer files are always brought into sync with the installed copy

Reconciliation behavior:

- default mode: overwrite differing manifest files and non-leaf layer files without backup
- reset mode: back up differing manifest files and non-leaf layer files, then overwrite
- identical files: no-op

This makes manifest files and non-leaf layers managed shared infrastructure
rather than user-protected leaf layers.

## Listing

Listing output is grouped by category and prints one of:

- `installed`: present only in installed seed sources
- `deployed`: present in both installed sources and user config
- `user-only`: present only in user config

Shared layers without a manifest are excluded.

## Interactive Picker

Interactive deploy proceeds in three steps:

1. select category
2. select one or more items
3. confirm the per-file plan

The item picker uses `fzf --multi` with a preview pane:

- devcontainers preview the manifest YAML
- images preview `Containerfile`
