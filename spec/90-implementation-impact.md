# Implementation Impact

**Status:** Implemented

## Purpose

This document records how the approved design work landed in the repository.

## Landed Areas

### Config Resolution Foundation

- `lib/dctl/common.sh` now owns `resolve_devcontainer_config()`
- canonical project naming and sibling discovery landed in shared helpers
- `bin/dctl` parses a global `--config` flag before dispatch

### Command Wiring

- `lib/dctl/ws.sh` resolves config for `up` and `reup`
- `lib/dctl/test.sh` resolves config before smoke-test validation
- `lib/dctl/init.sh` works with the user config and the runtime-generated merged config path (regenerated fresh, never cached)

### Layers and Dockerfiles

- `dctl` ships no image, no layer, and no manifest; `docs/examples/` holds
  copyable examples that no command reads and `make install` does not install
- manifest-driven multi-layer merge is implemented
- `lib/dctl/image.sh` resolves Dockerfiles from user config only and builds
  each managed parent before its child

### Project Registry

- `lib/dctl/config.sh` handles registry parsing and validation
- `schemas/projects.schema.yaml` ships with the project
- `bin/dctl` exposes `dctl config` as the registry command group entry point

### Tests

The bats suite now covers:

- config precedence
- registry parsing and validation
- manifest-driven merge regenerated fresh on every command
- Dockerfile hierarchy behavior
- install/systemd integration paths

## Result

The approved design was implemented across the CLI entrypoint, shell modules,
schema, and tests. The current codebase matches the architecture
described in the implemented spec set.
