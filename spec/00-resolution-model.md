# Shared Resolution Model

**Status:** Implemented

## Purpose

This document defines the implemented config resolution model used by `dctl`.
It covers `devcontainer.json` resolution, the user-config-only asset rule, and
the Dockerfile resolution used by `dctl image build`.

## Goals

- Support work-clone workflows without duplicating config across sibling clones
- Allow explicit overrides from the CLI and environment
- Support host-side project configuration in `projects.yaml`
- Keep user config, installed assets, and the runtime-generated merged config separated by XDG role
- Make the user config directory the only runtime-authoritative location
- Make selection deterministic and debuggable

## Devcontainer.json Precedence

`dctl` resolves `devcontainer.json` in this order:

1. `dctl --config <path>`
2. `DCTL_CONFIG`
3. `devcontainer-manifest` field in `~/.config/dctl/projects.yaml`
   (regenerates the merged config fresh from the manifest layers and returns
   `$XDG_RUNTIME_DIR/dctl/devcontainer/<name>/devcontainer.json`)
4. `.devcontainer/devcontainer.json` in the current workspace
5. Work-clone sibling discovery
6. `~/.config/dctl/default/devcontainer.json`

The winning source is logged. Missing explicit paths are immediate errors.

## XDG Layout

The implemented split is:

- `~/.config/dctl/`
  - project registry
  - user defaults
  - devcontainer manifests and layers
  - managed Dockerfiles
- `~/.local/share/dctl/`
  - schemas
- `$XDG_RUNTIME_DIR/dctl/devcontainer/`
  - runtime-generated merged `devcontainer.json` files, regenerated fresh on
    every command and never cached (fallback
    `${TMPDIR:-/tmp}/dctl-$(id -u)/dctl/devcontainer/`)

Config and data paths honor `XDG_CONFIG_HOME` and `XDG_DATA_HOME`; the generated
merged config honors `XDG_RUNTIME_DIR`.

## Global Managed-Asset Rule

If files are not in `~/.config/dctl/`, they cannot be used at runtime.

- `dctl` ships no image, no layer, and no manifest; `make install` installs
  only the CLI, its shell modules, and the schemas under `~/.local/share/dctl/`
- The user writes `~/.config/dctl/`: by hand, with a dotfiles manager, or with
  home-manager; [`docs/examples/`](../docs/examples/README.md) shows a starting
  point that no command reads
- Runtime operations read only from user config

This rule applies to both managed Dockerfiles and devcontainer manifests and
layers.

## Path Normalization

Filesystem paths participating in selection are normalized with `realpath`
before use. That includes CLI overrides, environment overrides, generated
config paths produced from registry manifests, workspace-derived sibling paths,
and the workspace folder itself.

## Resolution Logging

`dctl` logs the winning source only. Typical messages include:

- `Using devcontainer config from CLI flag: ...`
- `Using devcontainer config from project registry: <project> (manifest: <name>) -> ...`
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

No-arg `dctl image build` presents an interactive picker over the managed
images in user config and never consults the project registry. A target with no
Dockerfile there fails with guidance to add
`~/.config/dctl/images/<name>/Dockerfile`.

## Error Handling

- Missing CLI or env override paths fail immediately
- A registry manifest that cannot be merged (missing manifest/layer files, or
  `jq` absent) fails immediately and names the offending manifest
- Missing user default is a silent miss in the chain
- Exhausting the chain fails with guidance to run `dctl init` or pass `--config`
