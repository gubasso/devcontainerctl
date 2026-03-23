# Implementation Impact

## Purpose

This document maps the approved specs in this directory to the concrete code
changes required in the current repository. It is intentionally implementation-
oriented so the design docs can be executed as a sequence of scoped pull
requests.

## Sequencing

Implement in this order:

1. Phase A — Config resolution foundation
2. Phase B — Wire resolution into workspace commands
3. Phase C — Template and Dockerfile enhancements
4. Phase D — Project registry module and command surface
5. Phase E — Tests

Each phase can be its own PR, but later phases depend on earlier ones.

## Phase A — Config Resolution Foundation

### 1. `lib/dctl/common.sh`: add `resolve_devcontainer_config()`

Responsibility:

- Implement the resolution chain from
  [`00-resolution-model.md`](./00-resolution-model.md)
- Return the winning `devcontainer.json` path
- Log the selected source
- The registry lookup step (step 3 in the chain) should call a helper function
  that is initially stubbed to return empty in Phase A. Phase D fills in the
  real implementation via `config.sh`. This avoids duplicating registry logic.

Reason:

- `common.sh` already owns workspace path helpers and is the natural shared home
  for resolution primitives.

### 2. `lib/dctl/common.sh`: add `resolve_canonical_project_name()`

Responsibility:

- Derive the canonical project name from git remote or workspace basename
- Normalize work-clone names

Reason:

- Project registry lookup depends on this being reusable from multiple command
  paths.

### 3. `lib/dctl/common.sh`: add `resolve_work_clone_sibling()`

Responsibility:

- Implement the sibling discovery algorithm and git-repo guard

Reason:

- The logic is shared across config resolution and future diagnostics.

### 4. `bin/dctl`: add global `--config` flag parsing

Responsibility:

- Parse `dctl --config <path>` before subcommand dispatch
- Store the resolved CLI-level override so modules can consume it

Reason:

- The current entrypoint dispatches immediately on the first positional token,
  so global flags must be handled before command-group dispatch.

## Phase B — Wire Resolution Into Commands

### 5. `lib/dctl/ws.sh`: update `cmd_ws_up()` and `cmd_ws_reup()`

Responsibility:

- Resolve the effective `devcontainer.json`
- Pass `--config <resolved>` to `devcontainer up`
- Preserve `--workspace-folder "$WORKSPACE_FOLDER"`

### 6. `lib/dctl/test.sh`: update `cmd_test()`

Responsibility:

- Use the resolved config path instead of assuming the workspace-local file
- Read image information from the resolved config source
- Pass the resolved config to Dev Container CLI invocations used for validation

### 7. `lib/dctl/init.sh`: keep local writes, extend template discovery

Responsibility:

- Preserve current local scaffolding behavior
- Extend template discovery to include user templates
- Add `--list`

## Phase C — Template and Dockerfile Enhancements

### 8. `templates/base/devcontainer.json`: create new template

Responsibility:

- Add a minimal generic built-in template using `devimg/agents:latest`

### 9. `templates/coordinator/devcontainer.json`: create new template

Responsibility:

- Add the coordinator-oriented template with a parent-area read-only mount

### 10. `Makefile`: add new template dirs to `TEMPLATE_DIRS`

Responsibility:

- Install the `base` and `coordinator` templates into the data directory

### 11. `lib/dctl/init.sh`: extend `discover_templates()`

Responsibility:

- Scan both user template directories and installed template directories
- Apply user-overrides-installed precedence

### 12. `lib/dctl/image.sh`: extend `discover_image_targets()` and add Dockerfile resolution

Responsibility:

- Include user image override directories in target discovery
- Preserve current behavior for installed targets
- Add `resolve_dockerfile()` to implement the two-layer Dockerfile lookup:
  user override (`~/.config/dctl/images/<target>/Dockerfile`) before installed
  (`~/.local/share/dctl/images/<target>/Dockerfile`)
- When the project registry `DOCKERFILE` field is set, use it to redirect
  target name or provide a direct path. The registry lookup calls the same
  stubbed helper introduced in Phase A; Phase D fills in the real
  implementation via `config.sh`
- Update `cmd_image_build()` to call `resolve_dockerfile()` for the build context

## Phase D — Project Registry

### 13. New file `lib/dctl/config.sh`: project registry parsing and management

Responsibility:

- Encapsulate registry lookup and parsing
- Parse `.conf` files in an isolated scope
- Provide helpers reusable from `common.sh` and future commands

### 14. `bin/dctl`: source new module and add `dctl config`

Responsibility:

- Source `config.sh`
- Add a `config` subcommand group for future registry management commands

### 15. `Makefile`: add `config.sh` to `LIB_FILES`

Responsibility:

- Install the new module with the rest of the shell library

## Phase E — Tests

### 16. `tests/dctl_test.bats`: add resolution chain tests

Responsibility:

- Cover CLI flag, environment variable, registry, local file, sibling discovery,
  and global default behavior
- Add non-regression assertions for current local-file workflows

### 17. New file `tests/config_test.bats`: add project registry tests

Responsibility:

- Cover canonical name derivation
- Cover parsing of `.conf` files
- Cover `SIBLING_DISCOVERY=true/false`

### 18. `tests/dctl_test.bats`: add Dockerfile resolution tests

Responsibility:

- Cover user Dockerfile override (user dir wins over installed dir)
- Cover registry `DOCKERFILE` with managed target name
- Cover registry `DOCKERFILE` with direct filesystem path
- Cover CLI target wins over registry `DOCKERFILE` value
- Non-regression for current `dctl image build` behavior without registry

## Dependency Summary

- Phase A must land before any command wiring.
- Phase B depends on Phase A because it consumes shared resolution helpers.
- Phase C can start once command wiring is clear, but `init.sh` template work also
  depends on the template discovery rules.
- Phase D depends on the canonical naming and resolution concepts from Phase A.
- Phase E should be implemented alongside or immediately after each functional
  phase, but it is listed last to reflect the design dependency chain.
