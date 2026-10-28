# Dockerfile Hierarchy

**Status:** Implemented

## Purpose

This document describes the implemented Dockerfile resolution behavior for
`dctl image build`.

## Hierarchy

Managed Dockerfiles resolve through a single layer:

1. `~/.config/dctl/images/<name>/Dockerfile`

`dctl` ships no Dockerfile and installs none. The user writes one folder per
image under `~/.config/dctl/images/`; [`docs/examples/`](../docs/examples/README.md)
shows one.

## Resolution Algorithm

```text
resolve_dockerfile(target):
    if ~/.config/dctl/images/<target>/Dockerfile exists: return it
    error: no Dockerfile found for target
```

The relevant runtime XDG root is:

- `${XDG_CONFIG_HOME:-$HOME/.config}/dctl/images/`

## Parent Chain

A user image can build on another user image. A Dockerfile in
`~/.config/dctl/images/<name>/` that starts `FROM devimg/<parent>:latest` names
`<parent>` as a managed parent, and `dctl image build` reads these `FROM` lines
and builds every parent before its child:

- `FROM devimg/<name>:latest` names `<name>` as a managed parent, which must
  have its own `~/.config/dctl/images/<name>/Dockerfile`
- any other `devimg/` spelling, or a reference holding `$`, is refused
- any other reference is an external base and stays out of the graph
- a cycle in the graph is an error

## User Customization Pattern

1. Write `~/.config/dctl/images/<name>/Dockerfile`, by hand, with a dotfiles
   manager, or with home-manager
2. Run `dctl image build <name>`

`make install` never writes files under `~/.config/`.

## Architecture Notes

- devcontainer layers remain config-only artifacts
- images remain build-only artifacts
- each image installs what the user's projects need; each project owns its own
  dev environment setup
