# Per-Project Registry

**Status:** Implemented

## Purpose

This document describes the implemented host-side project registry used by
`dctl` for project-specific overrides and defaults.

## Location

The registry lives at:

```text
~/.config/dctl/projects.yaml
```

This path honors `${XDG_CONFIG_HOME:-$HOME/.config}/dctl/projects.yaml`.

## Format

The file is YAML. Each top-level key is a canonical project name and each value
is a flat mapping of project settings.

Example:

```yaml
org-repo:
  devcontainer: /home/alice/.cache/dctl/devcontainer/python/devcontainer.json

acme-docs:
  devcontainer: /home/alice/.cache/dctl/devcontainer/docs/devcontainer.json
  sibling_discovery: false
```

Format rules:

- top-level keys are canonical project names
- values are flat mappings
- comments are allowed
- unknown keys are rejected with an error
- invalid YAML is an error

## Host Dependency: `yq`

`dctl` reads and writes the registry with `yq`. If `yq` is missing when a
registry-backed operation runs, `dctl` errors with an install hint.

## Schema

The registry schema ships with the project at:

```text
schemas/projects.schema.yaml
```

and installs to:

```text
~/.local/share/dctl/schemas/projects.schema.yaml
```

Validation happens on every read. If `check-jsonschema` is present, `dctl` uses
it; otherwise it falls back to `yq`-based structural validation.

## Canonical Name Derivation

Canonical names resolve in this order:

1. derive from the git remote when available
2. otherwise use the workspace basename
3. strip the work-clone suffix after the first `.`

Examples:

- `https://github.com/org/repo.git` -> `org-repo`
- `git@github.com:org/repo.git` -> `org-repo`
- `repo.42-add-auth` -> `repo`

## Fields

### `devcontainer`

- path to a `devcontainer.json`
- participates in the main resolution chain

### `sibling_discovery`

- boolean
- defaults to `true`
- disables work-clone sibling discovery when set to `false`

## Resolution Behavior

The registry is third in the `devcontainer.json` precedence chain, after the
CLI flag and environment variable and before the local workspace file.

## Security and Trust Model

- the registry is parsed as data, not sourced as shell
- validation happens before field use
- path fields are checked before use
- the registry is only read from the XDG config path
