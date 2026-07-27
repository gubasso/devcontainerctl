# Devcontainer Metadata Extraction

**Status:** Implemented

## Purpose

This document records the completed move from legacy image-embedded shared
devcontainer settings into the template system.

## Problem Solved

The old approach mixed image-building concerns with shared devcontainer config.
That made the agents Dockerfile carry mounts, environment, and lifecycle
settings that belonged in templates instead.

## Landed Architecture

The implemented system now uses:

- `devcontainers/base/devcontainer.json` for shared infrastructure settings
- selectable templates for project-specific deltas
- `~/.config/dctl/devcontainer/` for user-editable config
- `$XDG_RUNTIME_DIR/dctl/devcontainer/` for the runtime-generated merged output,
  regenerated fresh on every command (never cached)

## Landed Changes

- `base` is the shared layer used by shipped manifests
- `general` became the user-facing generic template name
- `dctl init` now seeds config into XDG config and registers the project; the
  merge is regenerated fresh on every command under the XDG runtime dir rather
  than persisted
- the agents Dockerfile is now a pure container builder
- documentation and acceptance criteria were updated to the always-fresh model

## Migration Note

Projects configured before this change pick up the shared settings on the next
run of any config-resolving command, since the merged config is regenerated
fresh every time. A normal `dctl init` also re-registers the project and applies
the legacy `devcontainer:` → `devcontainer-manifest:` registry migration
automatically.

## Verification

The current test suite covers:

- shared-layer exclusion from manifest discovery
- merged config generation
- fresh regeneration reflecting config edits on every command
- registry manifest updates
- install behavior that leaves user config alone
