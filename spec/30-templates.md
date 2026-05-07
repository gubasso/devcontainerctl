# Devcontainer Template System

**Status:** Implemented

## Purpose

This document describes the implemented template system used by `dctl deploy`
and `dctl init`.

## Manifest Format

Each selectable config is defined by a YAML manifest declaring an ordered list
of layers. Example (`python.yaml`):

```yaml
layers:
  - base
  - agents
  - python
```

Manifests are validated against `schemas/compose.schema.yaml` (JSON Schema
Draft 2020-12). The only field is `layers` (non-empty array of strings).
No additional properties allowed.

## Template Catalog

Built-in layer directories and manifests in the repository:

**Layer directories** (each contains a `devcontainer.json`):

- `base/` — shared infrastructure layer (remote user, auth mounts, terminal env)
- `agents/` — shared agents layer (bubblewrap-friendly security profile and agent CLI config mounts)
- `general/` — minimal general-purpose sandbox on `devimg/agents:latest`
- `coordinator/` — coordinator workflow with parent-area visibility
- `python/` — Python project config on `devimg/python-dev:latest`
- `rust/` — Rust project config on `devimg/rust-dev:latest`
- `zig/` — Zig project config on `devimg/zig-dev:latest`

**Manifests** (each declares a composition):

- `general.yaml` — layers: `[base, agents, general]`
- `coordinator.yaml` — layers: `[base, agents, coordinator]`
- `python.yaml` — layers: `[base, agents, python]`
- `rust.yaml` — layers: `[base, agents, rust]`
- `zig.yaml` — layers: `[base, agents, zig]`

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

`base` owns the shared infrastructure settings. Selectable manifests add the
full ordered layer list whose last entry provides the project-specific image,
cache mounts, and lifecycle hooks.

## Merge Semantics

`dctl init` reads a deployed manifest from `~/.config/dctl/devcontainer/*.yaml`,
resolves each listed layer from user config, and merges them two-by-two with
`jq` in manifest order.

- scalar fields use last-wins behavior
- `mounts` are concatenated
- `postCreateCommand` is merged by key
- `containerEnv` and `remoteEnv` are merged by key
- JSONC comments are stripped before merge

## Discovery Rules

- `dctl deploy` reads installed manifests (`*.yaml`) from `~/.local/share/dctl/devcontainers/`
- `dctl init` reads deployed manifests (`*.yaml`) from `~/.config/dctl/devcontainer/`
- selectable entries are determined by manifest presence, not directory naming
- non-leaf layers (all except the last in a manifest) are managed shared infrastructure
- merge-time layer discovery reads user config only

## `dctl init` Behavior

`dctl init`:

1. selects a deployed manifest (`<name>.yaml`) from `~/.config/dctl/devcontainer/`
2. reads the selected manifest and merges all referenced user-config layers
   into `~/.cache/dctl/devcontainer/<name>/devcontainer.json`
3. reads the `.image` field from the merged cached config
4. for managed `devimg/<name>:latest` images, validates that the corresponding
   Dockerfile exists in `~/.config/dctl/images/<name>/Dockerfile`
5. for managed images, auto-builds the local image when missing
6. registers the manifest name in `~/.config/dctl/projects.yaml` — the
   entry contains `devcontainer-manifest:` only, plus `sibling_discovery: false` when
   explicitly overridden
7. runs `dctl test` (the workspace smoke test) against the resolved cache
8. prints a final summary with project, devcontainer, image status, cache and
   registry paths, and the smoke-test result

`dctl init` exits non-zero if the smoke test fails. If no deployed
devcontainers exist, `dctl init` fails and instructs the user to run `dctl
deploy`.

## `dctl deploy` Invariant

`dctl deploy` owns copying installed manifests and their referenced layers into user config.

- manifest files are always reconciled on every `deploy devcontainer ...` and
  `deploy --all*` invocation
- non-leaf manifest layers are always reconciled on every
  `deploy devcontainer ...` and `deploy --all*` invocation
- non-leaf layers are treated as managed shared infrastructure and are brought
  back into sync even in default mode when they drift
- leaf layers (the last layer in a manifest) are protected in default mode and
  only overwritten with `--reset`

See [`35-deploy.md`](./35-deploy.md) for the full deploy contract.
