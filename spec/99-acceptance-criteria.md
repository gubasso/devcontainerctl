# Acceptance Criteria

## Purpose

This document defines cross-cutting scenarios that must pass before the planned
config-resolution and template-system changes are considered complete.

## Acceptance Scenarios

### 1. Clean install non-regression

Scenario:

- User installs `dctl`
- User works in a project with a local `.devcontainer/devcontainer.json`
- User runs `dctl ws up`

Expected result:

- Behavior matches today's implementation
- The local config is selected
- Container identity remains keyed to the current workspace

### 2. Work-clone without local config

Scenario:

- Main repo: `repo/.devcontainer/devcontainer.json`
- Work-clone: `repo.42-feature/`
- Work-clone has no local config
- User runs `dctl ws up` from the work-clone

Expected result:

- `dctl` finds `repo/.devcontainer/devcontainer.json`
- `dctl` passes `--config <sibling-config>` to the Dev Container CLI
- `--workspace-folder` remains the work-clone path

### 3. Explicit environment override

Scenario:

- User sets `DCTL_CONFIG=/path/to/config.json`
- User runs `dctl ws up`

Expected result:

- The environment path wins over registry, local, sibling, and default sources
- The resolved source is logged

### 4. Explicit CLI override

Scenario:

- User runs `dctl --config /path/to/config.json ws up`

Expected result:

- The CLI flag wins over every other source
- The resolved source is logged

### 5. Project registry override

Scenario:

- `~/.config/dctl/projects/myrepo.conf` exists
- It contains `DEVCONTAINER_CONFIG=...`
- User runs `dctl ws up` from a matching workspace

Expected result:

- The registry entry is used
- The local workspace file is ignored for this command

### 6. User template discovery

Scenario:

- `~/.config/dctl/templates/custom/devcontainer.json` exists
- User runs `dctl init --list`

Expected result:

- `custom` appears in the template list
- User templates are included in discovery output

### 7. User template override

Scenario:

- Both `~/.config/dctl/templates/python/devcontainer.json` and
  `~/.local/share/dctl/templates/python/devcontainer.json` exist

Expected result:

- The user version wins during `dctl init --template python`

### 8. Coordinator template

Scenario:

- User runs `dctl init --template coordinator`

Expected result:

- The generated local `.devcontainer/devcontainer.json` contains the parent-area
  read-only mount described in [`30-templates.md`](./30-templates.md)

### 9. Resolution logging

Scenario:

- User runs `dctl ws up` in any case where a config source is selected

Expected result:

- `dctl` logs which source won
- The log is specific enough to identify the category and path

### 10. Sibling discovery opt-out

Scenario:

- `~/.config/dctl/projects/acme-repo.conf` exists
- It contains `SIBLING_DISCOVERY=false`
- Workspace `repo.docs/` has no local config
- Sibling `repo/.devcontainer/devcontainer.json` exists

Expected result:

- Sibling discovery is skipped
- Resolution continues to user global default or fails

### 11. User global default fallback

Scenario:

- Workspace has no local config, no sibling match, no project registry
- `~/.config/dctl/default/devcontainer.json` exists

Expected result:

- The global default is selected
- Resolution logging identifies the source as the user global default

### 12. Dockerfile user override

Scenario:

- `~/.config/dctl/images/agents/Dockerfile` exists (user custom)
- `~/.local/share/dctl/images/agents/Dockerfile` exists (installed)
- User runs `dctl image build agents`

Expected result:

- The user Dockerfile at `~/.config/dctl/images/agents/Dockerfile` is used
- The installed version is not used

### 13. Registry DOCKERFILE field (managed target)

Scenario:

- `~/.config/dctl/projects/org-repo.conf` contains `DOCKERFILE=python-dev`
- User runs `dctl image build` from a matching workspace without specifying a
  target on the CLI

Expected result:

- The registry `DOCKERFILE` value directs target selection
- Dockerfile resolution uses the two-layer hierarchy for the specified target
- If the user provides an explicit CLI target, the CLI target wins over the
  registry value

### 14. Registry DOCKERFILE field (direct path)

Scenario:

- `~/.config/dctl/projects/org-repo.conf` contains
  `DOCKERFILE=/home/alice/custom/Dockerfile`
- User runs `dctl image build` from a matching workspace

Expected result:

- The direct path is validated and used as the build context Dockerfile
- The two-layer managed lookup is not consulted

## Cross-Cutting Expectations

- No change to `dctl ws exec`, `dctl ws shell`, or `dctl ws run` container lookup
  semantics
- `dctl init` always writes local scaffolding
- `make install` never overwrites files in `~/.config/dctl`
- Built-in templates continue to work after the addition of user templates and
  user Dockerfile overrides

## Recommended Test Mapping

- Extend `tests/dctl_test.bats` for devcontainer.json config source precedence
  and `ws` behavior
- Extend `tests/dctl_test.bats` for Dockerfile resolution: user override,
  registry managed-target, registry direct-path, CLI-target-wins precedence
- Add `tests/config_test.bats` for project registry parsing, canonical-name
  derivation, and `SIBLING_DISCOVERY` opt-out
- Preserve current integration coverage for `make install` and local-template
  behavior
