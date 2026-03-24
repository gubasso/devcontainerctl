# Devcontainer Template System

## Purpose

This document formalizes the devcontainer template system used by `dctl init`
and extends it for generic and coordinator-style workflows.

## Current State

The current repository ships language templates under `templates/`:

- `python`
- `rust`
- `zig`

These are installed into `~/.local/share/dctl/templates/` by `make install`.
They contain only project-specific settings because shared infrastructure values
already live in the `devcontainer.metadata` label baked into
`images/agents/Dockerfile`.

This split is correct and should be preserved.

## Template Categories

The template system should support three categories:

1. **Language templates**
   - Existing templates: `python`, `rust`, `zig`
   - Purpose: add language-specific cache mounts and lifecycle hooks
2. **Base template**
   - New template: `base`
   - Purpose: minimal general-purpose config using `devimg/agents:latest`
3. **Coordinator template**
   - New template: `coordinator`
   - Purpose: generic agent/coordinator workflow with parent-directory access for
     sibling discovery

## Built-In Templates

### `base`

Future built-in file:

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

Future built-in file:

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
- `dctl init` deploys selected templates into the user config directory

## Image Label vs Template Split

### Image label owns shared infrastructure settings

The `devcontainer.metadata` label in `images/agents/Dockerfile` should remain
the home for:

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

Templates must not duplicate settings already owned by the image label.

## Composability

The Dev Container CLI automatically merges image metadata with
`devcontainer.json`. This design relies on that behavior.

Merge expectations to document for implementers:

- Scalars use last-wins behavior.
- Object keys are merged by key.
- Lifecycle hooks accumulate according to Dev Container metadata merge behavior.
- Arrays should be treated as union/append at the design level, while conflicts
  should be validated against actual Dev Container CLI semantics during
  implementation.

The important policy decision is that templates should stay minimal and avoid
re-stating label-owned defaults.

## Template Discovery

`dctl init` discovers templates from the installed templates directory only:

1. Installed templates: `~/.local/share/dctl/templates/`

Rules:

- Template names map to directory names.
- A valid template directory contains `devcontainer.json`.

## `dctl init` Changes

### `--list`

Add a `--list` flag that prints available templates and exits. This removes the
current dependency on `fzf` for non-interactive discovery.

### Deployment target

`dctl init` deploys the selected installed template to:

```text
~/.config/dctl/devcontainer/<name>/devcontainer.json
```

It then registers that deployed path in `~/.config/dctl/projects.yaml`.
`dctl init` does not write `.devcontainer/devcontainer.json`.

Without `--force`, an existing deployed config at the target path is preserved
and reused. With `--force`, the deployed config is overwritten from the
installed template source.

## Recommended Template Catalog

- `base`
- `coordinator`
- `python`
- `rust`
- `zig`

The first two become new built-ins. The latter three remain compatible with the
current repository structure and installation flow.

## Future File Layout

Built-in templates remain in the repository under:

```text
templates/<name>/devcontainer.json
```

Installed templates remain in:

```text
~/.local/share/dctl/templates/<name>/devcontainer.json
```

Deployed configs live in:

```text
~/.config/dctl/devcontainer/<name>/devcontainer.json
```
