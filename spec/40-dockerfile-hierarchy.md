# Dockerfile Hierarchy

## Purpose

This document defines how managed Dockerfiles are resolved and customized for
`dctl image build`.

## Current State

Today:

- Managed Dockerfiles live under `~/.local/share/dctl/images/<name>/Dockerfile`
- `dctl image build` discovers and builds from those installed locations
- Devcontainer templates refer to image tags such as `devimg/python-dev:latest`
- Templates and managed image Dockerfiles are intentionally separate concerns

This separation is correct and should remain.

## Proposed Hierarchy

Managed image Dockerfiles should resolve through two layers:

1. User custom Dockerfiles
   - `~/.config/dctl/images/<name>/Dockerfile`
2. Installed managed Dockerfiles
   - `~/.local/share/dctl/images/<name>/Dockerfile`

Future implementation should honor XDG variables:

- `${XDG_CONFIG_HOME:-$HOME/.config}/dctl/images/`
- `${XDG_DATA_HOME:-$HOME/.local/share}/dctl/images/`

## Resolution Algorithm

```text
resolve_dockerfile(target):
    if ~/.config/dctl/images/<target>/Dockerfile exists: return it
    if ~/.local/share/dctl/images/<target>/Dockerfile exists: return it
    error: no Dockerfile found for target
```

Selection rules:

- User overrides always win over installed managed Dockerfiles.
- `make install` populates only the data directory.
- `make install` never touches `~/.config/`.

## User Customization Pattern

The intended workflow is:

1. Copy a managed Dockerfile from the installed data dir into
   `~/.config/dctl/images/<name>/Dockerfile`
2. Modify the copied file
3. Run `dctl image build <name>`
4. `dctl image build` uses the user version automatically

This makes user overrides resilient to project upgrades because the install flow
does not overwrite files in `~/.config/`.

## Relationship to Project Registry

The project registry field `DOCKERFILE` can refer to either:

- A managed target name such as `agents` or `python-dev`
- A direct path to a custom Dockerfile

When it is a managed target name, resolution should use the hierarchy above.
When it is a path, resolution should validate the path directly.

## Template Pairing

No change to the current separation:

- Templates live in `templates/<name>/devcontainer.json`
- Managed images live in `images/<name>/Dockerfile`
- The link between them is the `"image"` field in `devcontainer.json`

This means:

- Templates remain config-only
- Images remain build-only
- `dctl init` does not need to scaffold Dockerfiles to preserve the current
  architecture

## Non-Goals

- This spec does not replace image-tag-based templates with build-based
  templates.
- This spec does not require `dctl init` to start generating `.devcontainer/Dockerfile`.
- This spec does not change the current image names or tags.

## Implementation Notes

The current `lib/dctl/image.sh` discovers image targets by scanning the data
directory only. Future implementation must merge user image directories and
installed image directories into one effective target list, with user overrides
taking precedence for matching names.
