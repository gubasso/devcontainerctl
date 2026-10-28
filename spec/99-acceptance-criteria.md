# Acceptance Criteria

**Status:** Implemented

## Purpose

This document records the cross-cutting scenarios that define the implemented
config-resolution and layer-system behavior.

The current bats suite covers the main acceptance areas:

- config precedence and error handling
- registry parsing, validation, and sibling-discovery opt-out
- manifest discovery, merge behavior, and fresh regeneration on every command
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
- It contains an entry for the canonical project with `devcontainer-manifest: example`
- User runs `dctl ws up` from a matching workspace

Expected result:

- The registry entry is used
- The local workspace file is ignored for this command

### 6. Manifest discovery

Scenario:

- `~/.config/dctl/devcontainer/example.yaml` exists
- User runs `dctl init` in a TTY with `fzf` available

Expected result:

- `example` appears in the picker
- Discovery is based on the manifests in user config only

### 7. Leaf layer mounts

Scenario:

- The user's `example` leaf layer declares a read-only mount
- User runs `dctl init --devcontainer example`

Expected result:

- The generated merged config at
  `$XDG_RUNTIME_DIR/dctl/devcontainer/example/devcontainer.json` contains the
  read-only mount from the `example` layer and the shared mounts from `base`

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

- `~/.config/dctl/images/example/Dockerfile` exists
- User runs `dctl image build example`

Expected result:

- The user Dockerfile is used
- No file outside `~/.config/dctl/images/` is consulted

### 12. Image build target selection

Scenario:

- `~/.config/dctl/images/example/Dockerfile` exists
- User runs `dctl image build example`

Expected result:

- `devimg/example:latest` is built from the user's Dockerfile

Scenario:

- `~/.config/dctl/images/example/Dockerfile` exists
- User runs `dctl image build` in a TTY with `fzf` available

Expected result:

- `dctl` presents a picker over the managed images in
  `~/.config/dctl/images/`
- `projects.yaml` is not consulted

Scenario:

- `~/.config/dctl/images/example/Dockerfile` exists
- User runs `dctl image build` with no args and `fzf` is missing

Expected result:

- `dctl` errors with a message naming `fzf`

Scenario:

- `~/.config/dctl/images/example/Dockerfile` exists
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

### 15. Manifest merge generates complete merged config

Scenario:

- User runs `dctl init --devcontainer example`

Expected result:

- The generated merged config contains all shared settings from `base`
- The generated merged config contains the settings of the selected leaf layer

### 16. Later layer wins for scalar fields

Scenario:

- `base` and the `example` leaf layer both set `name`
- User runs `dctl init --devcontainer example`

Expected result:

- The generated merged config contains all shared settings from `base`
- The generated merged config contains the leaf layer's `name` and `image`

### 17. Config edits apply on the next command

Scenario:

- User runs `dctl init --devcontainer example`
- User edits `~/.config/dctl/devcontainer/base/devcontainer.json`
- User runs `dctl ws reup` (no `dctl init` re-run)

Expected result:

- The merged config is regenerated fresh from the layers
- The regenerated config reflects the user's edit immediately

### 18. Automatic registry migration on init

Scenario:

- `~/.config/dctl/projects.yaml` has a legacy `devcontainer:` entry for the
  project
- User runs `dctl init --devcontainer example`

Expected result:

- The legacy `devcontainer:` key is migrated to `devcontainer-manifest:`
  automatically (no separate flag needed)
- The project is re-registered

### 19. User edits `base` layer config

Scenario:

- User runs `dctl init --devcontainer example`
- User edits `~/.config/dctl/devcontainer/base/devcontainer.json`
- User runs `dctl ws reup`

Expected result:

- The user's edit is preserved and merged into the freshly regenerated config
- No `dctl init` re-run is required to pick up the edit

### 20. User edits a leaf layer

Scenario:

- User runs `dctl init --devcontainer example`
- User edits `~/.config/dctl/devcontainer/example/devcontainer.json`
- User runs `dctl init` again

Expected result:

- The user's edited leaf layer is preserved
- The generated merged config reflects the user's custom leaf settings merged with
  `base`

### 21. Generated-output deletion is safe

Scenario:

- User deletes `$XDG_RUNTIME_DIR/dctl/` entirely
- User runs `dctl init --devcontainer example`

Expected result:

- `dctl` regenerates the merged config without error
- Behavior is identical to a fresh install

### 22. Dockerfile is a pure container builder

Scenario:

- Docker image is built from `~/.config/dctl/images/example/Dockerfile`

Expected result:

- Shared devcontainer config lives in devcontainer layers, not in the Dockerfile
- The Dockerfile focuses on image construction only

### 23. Shared layers are excluded from config discovery

Scenario:

- `~/.config/dctl/devcontainer/base/devcontainer.json` exists
- User runs `dctl init` in a TTY with `fzf` available

Expected result:

- `base` does not appear in the selectable config list unless a `base.yaml`
  manifest exists
- Only manifest-backed configs are listed

### 24. `make install` scope

Scenario:

- User runs `make install`

Expected result:

- Files are written only to the bin, lib, and schema locations
- No image, layer, or manifest is installed
- No files are written to `~/.config/dctl/` or the runtime generated dir

### 25. `dctl deploy` is gone

Scenario:

- User runs `dctl deploy`

Expected result:

- `dctl` fails with `Unknown command group: deploy`

### 26. `make uninstall` removes legacy seed files

Scenario:

- An older release left Dockerfiles under `~/.local/share/dctl/images/` and
  manifests and layers under `~/.local/share/dctl/devcontainers/`
- User runs `make uninstall`

Expected result:

- Those files and their empty folders are removed
- Nothing under `~/.config/dctl/` is touched

### 27. Image build with no Dockerfile

Scenario:

- `~/.config/dctl/images/` holds no `<name>/Dockerfile`
- User runs `dctl image build --all`

Expected result:

- `dctl` fails with guidance to add one folder per image with a Dockerfile,
  `~/.config/dctl/images/<name>/Dockerfile`, pointing at `docs/examples/` in
  the devcontainerctl repository

### 28. `init` registers from user config only

Scenario:

- `~/.config/dctl/devcontainer/example/devcontainer.json` exists
- `~/.config/dctl/images/example/Dockerfile` exists
- User runs `dctl init --devcontainer example`

Expected result:

- The merged config is generated from user config
- The project registry stores the manifest name (`devcontainer-manifest: example`)
- The merged config is generated fresh under `$XDG_RUNTIME_DIR/dctl/devcontainer/example/devcontainer.json` (never cached)
- The registry does not store image-selection duplication from `init`
- The registry does not store paths

### 29. `init` errors when there is no manifest

Scenario:

- `~/.config/dctl/devcontainer/` has no manifest
- User runs `dctl init`

Expected result:

- `dctl` fails with guidance to add `<name>.yaml` and its layer folders there,
  pointing at `docs/examples/` in the devcontainerctl repository

### 30. `init` auto-builds missing managed images

Scenario:

- `~/.config/dctl/devcontainer/example/devcontainer.json` references
  `devimg/example:latest`
- `~/.config/dctl/images/example/Dockerfile` exists
- `docker image inspect devimg/example:latest` fails
- User runs `dctl init --devcontainer example`

Expected result:

- `dctl` automatically runs `dctl image build example`
- registry registration and the smoke test proceed after a successful build
