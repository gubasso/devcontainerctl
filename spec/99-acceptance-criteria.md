# Acceptance Criteria

**Status:** Implemented

## Purpose

This document records the cross-cutting scenarios that define the implemented
config-resolution and template-system behavior.

The current bats suite covers the main acceptance areas:

- config precedence and error handling
- registry parsing, validation, and sibling-discovery opt-out
- template discovery, merge behavior, and cache invalidation
- Dockerfile hierarchy behavior
- install and systemd integration paths

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

- `~/.config/dctl/projects.yaml` exists
- It contains an entry for the canonical project with `devcontainer-manifest: python`
- User runs `dctl ws up` from a matching workspace

Expected result:

- The registry entry is used
- The local workspace file is ignored for this command

### 6. Installed template discovery

Scenario:

- `~/.local/share/dctl/devcontainers/python/devcontainer.json` exists
- User runs `dctl deploy --list-devcontainers`

Expected result:

- `python` appears in the deploy list
- Discovery is based on installed templates only

### 7. Coordinator template

Scenario:

- User runs `dctl init --devcontainer coordinator`

Expected result:

- The cached config at
  `~/.cache/dctl/devcontainer/coordinator/devcontainer.json` contains the
  parent-area read-only mount from the `coordinator` template and the shared
  mounts from `base`

### 8. Resolution logging

Scenario:

- User runs `dctl ws up` in any case where a config source is selected

Expected result:

- `dctl` logs which source won
- The log is specific enough to identify the category and path

### 9. Sibling discovery opt-out

Scenario:

- `~/.config/dctl/projects.yaml` contains `acme-repo: { sibling_discovery: false }`
- Workspace `repo.docs/` has no local config
- Sibling `repo/.devcontainer/devcontainer.json` exists

Expected result:

- Sibling discovery is skipped
- Resolution continues to user global default or fails

### 10. User global default fallback

Scenario:

- Workspace has no local config, no sibling match, no project registry
- `~/.config/dctl/default/devcontainer.json` exists

Expected result:

- The global default is selected
- Resolution logging identifies the source as the user global default

### 11. Dockerfile user override

Scenario:

- `~/.config/dctl/images/agents/Dockerfile` exists
- User runs `dctl image build agents`

Expected result:

- The user Dockerfile is used
- Installed files are not consulted at runtime

### 12. Image build target selection

Scenario:

- `~/.config/dctl/images/agents/Dockerfile` exists
- User runs `dctl image build agents`

Expected result:

- `devimg/agents:latest` is built from the deployed managed Dockerfile

Scenario:

- `~/.config/dctl/images/agents/Dockerfile` exists
- User runs `dctl image build` in a TTY with `fzf` available

Expected result:

- `dctl` presents a picker over deployed managed images from
  `~/.config/dctl/images/`
- `projects.yaml` is not consulted

Scenario:

- `~/.config/dctl/images/agents/Dockerfile` exists
- User runs `dctl image build` with no args and `fzf` is missing

Expected result:

- `dctl` errors with a message naming `fzf`

Scenario:

- `~/.config/dctl/images/agents/Dockerfile` exists
- User runs `dctl image build` with no args and stdin is not a TTY

Expected result:

- `dctl` errors with a message about requiring a terminal

### 13. Schema validation

Scenario:

- `~/.config/dctl/projects.yaml` contains an unrecognized key or invalid type
- User runs any `dctl` command that reads the registry

Expected result:

- `dctl` reports a schema validation error
- The command does not proceed with invalid config

### 15. Manifest merge generates complete cached config

Scenario:

- User runs `dctl init --devcontainer python`

Expected result:

- The cached config contains all shared settings from `base`
- The cached config contains Python-specific settings from the selected leaf layer

### 16. General manifest merge

Scenario:

- User runs `dctl init --devcontainer general`

Expected result:

- The cached config contains all shared settings from `base`
- The cached config contains the general leaf layer's `name`, `image`, and
  pre-commit bootstrap

### 17. Cache invalidation on config change

Scenario:

- User runs `dctl init --devcontainer python`
- User edits `~/.config/dctl/devcontainer/base/devcontainer.json`
- User runs `dctl init` again

Expected result:

- The cached config is regenerated because a config file is newer
- The new cached config reflects the user's edit

### 18. Force regeneration

Scenario:

- User runs `dctl init --force --devcontainer python`

Expected result:

- Config files are re-seeded from installed templates
- The cached config is regenerated regardless of mtime freshness

### 19. User edits `base` layer config

Scenario:

- User runs `dctl init --devcontainer python`
- User edits `~/.config/dctl/devcontainer/base/devcontainer.json`
- User runs `dctl init --force --devcontainer python`

Expected result:

- With `--force`, config is re-seeded from templates and cache regenerated
- Without `--force`, the user's edit is preserved and merged into cache

### 20. User edits a template config

Scenario:

- User runs `dctl init --devcontainer python`
- User edits `~/.config/dctl/devcontainer/python/devcontainer.json`
- User runs `dctl init` again

Expected result:

- The user's edited template config is preserved
- The cached config reflects the user's custom template settings merged with
  `base`

### 21. Cache deletion is safe

Scenario:

- User deletes `~/.cache/dctl/` entirely
- User runs `dctl init --devcontainer python`

Expected result:

- `dctl` regenerates the cached config without error
- Behavior is identical to a fresh install

### 22. Dockerfile is a pure container builder

Scenario:

- Docker image is built from `images/agents/Dockerfile`

Expected result:

- Shared devcontainer config lives in templates, not in the Dockerfile
- The Dockerfile focuses on image construction only

### 23. Shared layers are excluded from config discovery

Scenario:

- `~/.local/share/dctl/devcontainers/base/devcontainer.json` exists
- User runs `dctl deploy --list-devcontainers`

Expected result:

- `base` does not appear in the selectable config list unless a `base.yaml`
  manifest exists
- Only manifest-backed configs are listed

### 24. `make install` scope

Scenario:

- User runs `make install`

Expected result:

- Files are written only to installed data/bin/lib locations
- No files are written to `~/.config/dctl/` or `~/.cache/dctl/`

### 25. `deploy --list` shows deployment state for both categories

Scenario:

- User runs `dctl deploy --list`

Expected result:

- Output is grouped into devcontainers and images
- Each listed entry is marked as `installed`, `deployed`, or `user-only`
- Shared layers without manifests are excluded

### 26. `deploy devcontainer` seeds user config

Scenario:

- User runs `dctl deploy devcontainer python`

Expected result:

- `~/.config/dctl/devcontainer/python/` is created
- `~/.config/dctl/devcontainer/python.yaml` is deployed
- all non-leaf layers referenced by the installed manifest are also deployed
- the project registry is unchanged

### 27. `deploy --reset` backs up and overwrites shipped files

Scenario:

- `~/.config/dctl/images/python-dev/Dockerfile` exists and differs from the
  installed copy
- User runs `dctl deploy image python-dev --reset`

Expected result:

- The existing file is backed up to `Dockerfile.bak.<UTC-ISO-DATE>`
- The shipped Dockerfile is copied into place
- user-only neighboring files are untouched

### 28. `init` registers from deployed config only

Scenario:

- `~/.config/dctl/devcontainer/python/devcontainer.json` exists
- `~/.config/dctl/images/python-dev/Dockerfile` exists
- User runs `dctl init --devcontainer python`

Expected result:

- The cached config is generated from user config
- The project registry stores the manifest name (`devcontainer-manifest: python`)
- The cached config is generated under `~/.cache/dctl/devcontainer/python/devcontainer.json`
- The registry does not store image-selection duplication from `init`
- The registry does not store paths

### 29. `init` errors when nothing is deployed

Scenario:

- `~/.config/dctl/devcontainer/` has no selectable deployed devcontainers
- User runs `dctl init`

Expected result:

- `dctl` fails with guidance to run `dctl deploy`

### 30. `init` auto-builds missing managed images

Scenario:

- `~/.config/dctl/devcontainer/python/devcontainer.json` references
  `devimg/python-dev:latest`
- `~/.config/dctl/images/python-dev/Dockerfile` exists
- `docker image inspect devimg/python-dev:latest` fails
- User runs `dctl init --devcontainer python`

Expected result:

- `dctl` automatically runs `dctl image build python-dev`
- cache generation and registry registration proceed after a successful build
