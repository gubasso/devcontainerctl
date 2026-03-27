# Devcontainer Resolution

**Status:** Implemented

## Purpose

This document describes the implemented `devcontainer.json` resolution behavior
for `dctl`.

## Resolution Algorithm

```text
resolve_devcontainer_config():
    if --config flag provided:                          return flag value
    if DCTL_CONFIG env var set:                         return env var value
    if projects.yaml has devcontainer for project:      return registry value
    if local .devcontainer/devcontainer.json exists:    return it
    if work-clone sibling has config:                   return sibling config
    if ~/.config/dctl/default/devcontainer.json exists: return it
    error: no config found, run 'dctl init'
```

All path comparisons use normalized `realpath` values.

## Source Definitions

### CLI Flag

- `dctl --config <path>`
- highest precedence
- missing path is an immediate error

### Environment Variable

- `DCTL_CONFIG`
- used when the CLI flag is absent
- missing path is an immediate error

### Project Registry

- source: `devcontainer` field in `~/.config/dctl/projects.yaml`
- participates only when present for the canonical project
- missing registry target path is an error

### Local Project File

- source: `.devcontainer/devcontainer.json` in the current workspace

### Work-Clone Sibling

- source: sibling repo config discovered via the shared resolution model

### User Global Default

- source: `~/.config/dctl/default/devcontainer.json`
- silent miss if absent

## Integration with the Dev Container CLI

When a config is resolved, `dctl` invokes the Dev Container CLI with:

```text
devcontainer up --workspace-folder "$WORKSPACE_FOLDER" --config "$resolved_path"
```

The workspace folder remains the current directory even when the resolved
config lives elsewhere.

## Command Impact

### `dctl ws up`

- resolves config first
- passes `--config <resolved-path>`

### `dctl ws reup`

- same as `ws up`
- adds `--remove-existing-container`

### `dctl test`

- resolves config first
- reads image information from the resolved config
- passes the resolved config through to Dev Container CLI operations

### `dctl init`

- seeds config files into `~/.config/dctl/devcontainer/`
- writes merged output to `~/.cache/dctl/devcontainer/<name>/devcontainer.json`
- registers the generated cache path in `~/.config/dctl/projects.yaml`
- does not write local workspace `.devcontainer/` files

### `dctl ws exec`, `dctl ws shell`, `dctl ws run`

- resolve config via the same precedence chain (needed for the `--config` pass-through to `devcontainer exec`)
- operate on already-running containers selected by workspace label

## Failure Modes

- no config found: fail with guidance to run `dctl init` or pass `--config`
- explicit override path missing: fail immediately
- registry path missing: fail immediately
- invalid JSON: let the Dev Container CLI report it

## Logging Requirements

When a source wins, `dctl` logs it at normal verbosity. The log identifies the
source category and the resolved path.
