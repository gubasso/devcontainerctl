# Shared Resolution Model

**Status:** Implemented

## Purpose

This document defines the implemented config resolution model used by `dctl`.
It covers both `devcontainer.json` resolution and the narrower Dockerfile
resolution used by `dctl image build`.

## Goals

- Support work-clone workflows without duplicating config across sibling clones
- Allow explicit overrides from the CLI and environment
- Support host-side project configuration in `projects.yaml`
- Keep user config, installed assets, and generated cache separated by XDG role
- Make selection deterministic and debuggable

## Devcontainer.json Precedence

`dctl` resolves `devcontainer.json` in this order:

1. `dctl --config <path>`
2. `DCTL_CONFIG`
3. `devcontainer` field in `~/.config/dctl/projects.yaml`
4. `.devcontainer/devcontainer.json` in the current workspace
5. Work-clone sibling discovery
6. `~/.config/dctl/default/devcontainer.json`

The winning source is logged. Missing explicit paths are immediate errors.

## XDG Layout

The implemented split is:

- `~/.config/dctl/`
  - project registry
  - user defaults
  - deployed devcontainer config
  - user Dockerfile overrides
- `~/.local/share/dctl/`
  - installed templates
  - installed managed Dockerfiles
  - schemas
- `~/.cache/dctl/`
  - generated merged `devcontainer.json` files

All paths honor `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, and `XDG_CACHE_HOME`.

## Path Normalization

Filesystem paths participating in selection are normalized with `realpath`
before use. That includes CLI overrides, environment overrides, registry paths,
workspace-derived sibling paths, and the workspace folder itself.

## Resolution Logging

`dctl` logs the winning source only. Typical messages include:

- `Using devcontainer config from CLI flag: ...`
- `Using devcontainer config from project registry: ...`
- `Using devcontainer config from sibling repo: ...`
- `Using Dockerfile override from ...`

## Dev Container CLI Integration

`dctl` resolves the effective config path before invoking the Dev Container CLI
and passes it via `--config`. `--workspace-folder` remains the current
workspace directory, so container identity stays keyed to the current clone.

## Work-Clone Sibling Discovery

Sibling discovery is deterministic:

1. Take the current workspace basename
2. If it contains `.`, strip everything after the first `.`
3. Look for a sibling directory with that base name
4. Require that sibling to be a git repo
5. Require `.devcontainer/devcontainer.json` in that sibling

Sibling discovery is skipped when the project registry sets
`sibling_discovery: false`.

## Dockerfile Resolution Scope

Dockerfile resolution applies only to `dctl image build`.

For a managed target, resolution is:

1. `~/.config/dctl/images/<target>/Dockerfile`

If the project registry provides `dockerfile: /absolute/path`, that direct path
is validated and used without the managed lookup. Installed Dockerfiles are seed
sources only and must be copied into user config by `dctl init`.

## Error Handling

- Missing CLI or env override paths fail immediately
- Missing registry `devcontainer` paths fail immediately and name the registry
- Missing user default is a silent miss in the chain
- Exhausting the chain fails with guidance to run `dctl init` or pass `--config`
