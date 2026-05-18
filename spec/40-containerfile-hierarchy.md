# Containerfile Hierarchy

**Status:** Implemented

## Purpose

This document describes the implemented Containerfile resolution behavior for
`dctl image build`.

## Hierarchy

Managed Containerfiles resolve through a single layer:

1. `~/.config/dctl/images/<name>/Containerfile`

Installed files under `~/.local/share/dctl/images/` are seed sources only and
are never used directly at runtime.

## Resolution Algorithm

```text
resolve_containerfile(target):
    if ~/.config/dctl/images/<target>/Containerfile exists: return it
    error: no Containerfile found for target
```

The relevant runtime XDG root is:

- `${XDG_CONFIG_HOME:-$HOME/.config}/dctl/images/`

Installed Containerfiles live under `${XDG_DATA_HOME:-$HOME/.local/share}/dctl/images/`
only so `dctl deploy image ...` can seed them into user config.

## User Customization Pattern

1. Run `dctl deploy image <name>` to seed the managed Containerfile into
   `~/.config/dctl/images/<name>/`
2. Modify the seeded Containerfile as needed
3. Run `dctl image build <name>`

`make install` never overwrites files under `~/.config/`.

## Architecture Notes

- devcontainer templates remain config-only artifacts
- images remain build-only artifacts
- installed image files are seed sources only
- `dctl deploy image ...` seeds the managed Containerfile into
  `~/.config/dctl/images/`
