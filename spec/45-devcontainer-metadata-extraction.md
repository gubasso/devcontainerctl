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

- `templates/_base/devcontainer.json` for shared infrastructure settings
- selectable templates for project-specific deltas
- `~/.config/dctl/devcontainer/` for user-editable config
- `~/.cache/dctl/devcontainer/` for merged generated output

## Landed Changes

- `_base` was added as the internal shared template
- `general` became the user-facing generic template name
- `dctl init` now seeds config into XDG config, merges into XDG cache, and
  registers the generated path
- the agents Dockerfile is now a pure container builder
- documentation and acceptance criteria were updated to the cache-based model

## Migration Note

Projects configured before this change needed a fresh `dctl init` or
`dctl init --force` so the shared settings moved into the new template-driven
config flow.

## Verification

The current test suite covers:

- `_base` exclusion from discovery
- merged cache generation
- cache invalidation on config edits
- registry path updates
- install behavior that leaves config/cache alone
