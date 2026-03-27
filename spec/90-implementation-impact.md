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
- `lib/dctl/init.sh` works with deployed config and generated cache paths

### Templates and Dockerfiles

- `templates/general/` and `templates/coordinator/` are shipped and installed
- `_base` plus template merge is implemented
- `lib/dctl/image.sh` resolves user-overridden versus installed Dockerfiles

### Project Registry

- `lib/dctl/config.sh` handles registry parsing and validation
- `schemas/projects.schema.yaml` ships with the project
- `bin/dctl` exposes `dctl config` as the registry command group entry point

### Tests

The bats suite now covers:

- config precedence
- registry parsing and validation
- template merge and cache invalidation
- Dockerfile hierarchy behavior
- install/systemd integration paths

## Result

The approved design was implemented across the CLI entrypoint, shell modules,
templates, schema, and tests. The current codebase matches the architecture
described in the implemented spec set.
