# Dockerfile Hierarchy

**Status:** Implemented

## Purpose

This document describes the implemented Dockerfile resolution behavior for
`dctl image build`.

## Hierarchy

Managed Dockerfiles resolve through two layers:

1. `~/.config/dctl/images/<name>/Dockerfile`
2. `~/.local/share/dctl/images/<name>/Dockerfile`

User overrides always win over installed Dockerfiles.

## Resolution Algorithm

```text
resolve_dockerfile(target):
    if ~/.config/dctl/images/<target>/Dockerfile exists: return it
    if ~/.local/share/dctl/images/<target>/Dockerfile exists: return it
    error: no Dockerfile found for target
```

The relevant XDG roots are:

- `${XDG_CONFIG_HOME:-$HOME/.config}/dctl/images/`
- `${XDG_DATA_HOME:-$HOME/.local/share}/dctl/images/`

## User Customization Pattern

1. Copy an installed managed Dockerfile into `~/.config/dctl/images/<name>/`
2. Modify it
3. Run `dctl image build <name>`

`make install` never overwrites files under `~/.config/`.

## Relationship to Project Registry

The registry field `dockerfile` can be:

- a managed target name such as `agents` or `python-dev`
- a direct filesystem path to a Dockerfile

Managed target names still use the two-layer hierarchy. Direct paths are
validated directly.

## Architecture Notes

- templates remain config-only artifacts
- images remain build-only artifacts
- `dctl init` does not scaffold Dockerfiles
