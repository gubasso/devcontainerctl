# Devcontainer Resolution

## Purpose

This document defines how `dctl` resolves the effective `devcontainer.json`
file for workspace lifecycle commands. It builds on the shared model in
[`00-resolution-model.md`](./00-resolution-model.md) and applies it specifically
to `devcontainer.json`.

## Resolution Algorithm

The required algorithm is:

```text
resolve_devcontainer_config():
    if --config flag provided:                          return flag value
    if DCTL_CONFIG env var set:                          return env var value
    if projects.yaml has entry for canonical project
       AND entry contains devcontainer key:              return registry value
    if local .devcontainer/devcontainer.json exists:     return it
    if work-clone sibling has config:                    return sibling's config
    if ~/.config/dctl/default/devcontainer.json exists:  return it
    error: no config found, run 'dctl init'
```

All path checks and comparisons use normalized `realpath` values.

## Source Definitions

### CLI Flag

- Flag form: `dctl --config <path>`
- Highest precedence
- Missing path is an immediate error

### Environment Variable

- Variable: `DCTL_CONFIG`
- Used only if the CLI flag is absent
- Missing path is an immediate error

### Project Registry

- Source: `devcontainer` key for the canonical project name in
  `~/.config/dctl/projects.yaml`
- Used only if neither explicit source is set
- The registry only participates if `projects.yaml` exists, contains an entry
  for the canonical project, **and** that entry has a `devcontainer` key. If
  the entry exists but defines only other keys (e.g., `dockerfile`,
  `sibling_discovery`), resolution continues to the next source in the chain.
- If `devcontainer` is set but points to a missing path, that is an error
  that names the project and registry file

### Local Project File

- Path: `.devcontainer/devcontainer.json` in the current workspace
- Current behavior today, retained in the future chain

### Work-Clone Sibling

- Derived using the sibling algorithm from
  [`00-resolution-model.md`](./00-resolution-model.md)
- Used when the local workspace has no usable config

### User Global Default

- Path: `~/.config/dctl/default/devcontainer.json`
- Intended as a personal fallback when the workspace and registry provide no
  project-specific config
- This is a silent fallback: if the file does not exist, resolution continues
  to the final error. The file is never required — its absence simply means
  there is no user default configured.

## Integration with the Dev Container CLI

Once `dctl` resolves the config path, it should invoke the Dev Container CLI
like this:

```text
devcontainer up --workspace-folder "$WORKSPACE_FOLDER" --config "$resolved_path"
```

Required invariants:

- `--workspace-folder` remains the current directory.
- The resolved config path can be outside the workspace.
- `${localWorkspaceFolderBasename}` still resolves relative to the current
  workspace, which is correct for work-clone naming.
- Container labels based on the workspace folder remain unique per clone.

## Command Impact

### `dctl ws up`

- Must resolve the config path before calling `devcontainer up`.
- Must pass `--config <resolved-path>` when invoking the Dev Container CLI.

### `dctl ws reup`

- Same as `ws up`, plus `--remove-existing-container`.

### `dctl test`

- Must resolve the config path before validation.
- Any operation that currently reads the local config file directly must switch
  to the resolved config path.
- Validation still delegates JSON correctness to the Dev Container CLI.

### `dctl init`

- No change to resolution behavior.
- Scaffolding always writes to the local workspace at
  `.devcontainer/devcontainer.json`.
- `init` remains a local-write command even when the runtime resolution chain can
  read from non-local sources.

### `dctl ws exec`, `dctl ws shell`, `dctl ws run`

- No config-resolution change.
- These commands operate on already-running containers located by workspace label.

## Failure Modes

### No config found

If all sources miss, fail with guidance:

```text
No devcontainer config found for <workspace>. Run 'dctl init' or pass --config.
```

### Resolved path does not exist

If an explicit (CLI flag, env var) or registry path is set but points to a
missing file, error immediately and show the path that failed. The user global
default is a silent fallback — if it does not exist, resolution continues to
the final "no config found" error rather than failing on the missing default.

### Invalid JSON

Do not pre-parse JSON in `dctl`. Pass the resolved file through to the Dev
Container CLI and let it report JSON syntax or schema errors.

### Ambiguous work-clone match

The initial algorithm only checks one deterministic sibling candidate. This spec
still reserves an explicit ambiguity failure mode for any future implementation
that broadens matching beyond one candidate:

```text
Ambiguous work-clone config match for <workspace>. Pass --config explicitly.
```

### Sibling config exists but sibling is not a git repo

Do not use it. Treat sibling discovery as a miss and continue to the global
default.

## Logging Requirements

When a config source wins, `dctl` should log it at normal `log` verbosity.

Examples:

- `Using devcontainer config from local workspace file`
- `Using devcontainer config from project registry: org-repo in projects.yaml`
- `Using devcontainer config from sibling repo /home/alice/projects/repo`
- `Using devcontainer config from ~/.config/dctl/default/devcontainer.json`

## Examples

### Local project wins

Workspace:

```text
/home/alice/projects/repo
```

If `/home/alice/projects/repo/.devcontainer/devcontainer.json` exists and no
higher-precedence source is set, it wins.

### Work-clone falls back to sibling

Workspace:

```text
/home/alice/projects/repo.42-feature
```

Sibling:

```text
/home/alice/projects/repo/.devcontainer/devcontainer.json
```

If the work-clone has no local config, the sibling config is selected while the
workspace folder remains `/home/alice/projects/repo.42-feature`.

### Global default wins

If the workspace has no local config, no sibling match, and no project registry,
then `~/.config/dctl/default/devcontainer.json` becomes the fallback.

## Implementation Constraints

- The current codebase uses local-file helpers such as
  `workspace_devcontainer_file()` in `lib/dctl/common.sh`. Future implementation
  must add a resolved-config path flow rather than assuming the workspace-local
  path everywhere.
- The test command currently reads `"image"` directly from the local file with
  grep and sed. That logic must move to the resolved config path.
