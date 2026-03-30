# Dockerfile Hierarchy

**Status:** Implemented

## Purpose

This document describes the implemented Dockerfile resolution behavior for
`dctl image build`.

## Hierarchy

Managed Dockerfiles resolve through a single layer:

1. `~/.config/dctl/images/<name>/Dockerfile`

Installed files under `~/.local/share/dctl/images/` are seed sources only and
are never used directly at runtime.

## Resolution Algorithm

```text
resolve_dockerfile(target):
    if ~/.config/dctl/images/<target>/Dockerfile exists: return it
    error: no Dockerfile found for target
```

The relevant runtime XDG root is:

- `${XDG_CONFIG_HOME:-$HOME/.config}/dctl/images/`

Installed Dockerfiles live under `${XDG_DATA_HOME:-$HOME/.local/share}/dctl/images/`
only so `dctl init` can seed them into user config.

## User Customization Pattern

1. Run `dctl init --template <name>` to seed the managed Dockerfile into
   `~/.config/dctl/images/<name>/`
2. Modify the seeded Dockerfile as needed
3. Run `dctl image build <name>`

`make install` never overwrites files under `~/.config/`.

## Relationship to Project Registry

The registry field `dockerfile` can be:

- a managed target name such as `agents` or `python-dev`
- a direct filesystem path to a Dockerfile

Managed target names use user-config Dockerfile resolution. Direct paths are
validated directly.

## Architecture Notes

- devcontainer templates remain config-only artifacts
- images remain build-only artifacts
- installed image files are seed sources only
- `dctl init` seeds the template-associated Dockerfile to `~/.config/dctl/images/`
  on first init (or with `--force`/`--reset`/`--image-only`)
