# Per-Project Registry

## Purpose

This document defines the host-side project registry used by `dctl` to inject
project-specific config without requiring every work-clone to carry its own
local `.devcontainer` files.

## Location

The project registry is a single YAML file:

```text
~/.config/dctl/projects.yaml
```

The design must honor `${XDG_CONFIG_HOME:-$HOME/.config}/dctl/projects.yaml` in
future implementation.

A single file is preferred over a directory of per-project files because:

- All project entries are visible in one place.
- Easier to edit, version-control, and back up.
- YAML supports comments and structured data natively.

## Format

The file is YAML, parsed by `yq` on the host. Each top-level key is a
canonical project name, and its value is a mapping of project settings.

Example:

```yaml
# ~/.config/dctl/projects.yaml

org-repo:
  devcontainer: /home/alice/.config/dctl/shared/org-repo/devcontainer.json
  dockerfile: python-dev
  image: devimg/python-dev:latest
  sibling_discovery: true

acme-docs:
  sibling_discovery: false

personal-api:
  dockerfile: /home/alice/custom/Dockerfile
```

Format rules:

- Top-level keys are canonical project names (see derivation below).
- Values are flat mappings — no nesting beyond one level.
- Comments start with `#`.
- Unknown keys are ignored by the initial implementation but preserved by
  `yq` operations.
- Invalid YAML is an error with a message pointing to the file.

## Host Dependency: `yq`

This design requires `yq` (https://github.com/mikefarah/yq) on the host.

Justification:

- `yq` is a single static binary, trivial to install.
- Avoids arbitrary code execution risks of shell-sourced `.conf` files.
- YAML is a natural fit for structured project config.
- `yq` is already installed in the container images via `mise`; requiring it
  on the host aligns the toolchain.

`dctl` should check for `yq` at startup (via `require_cmd yq`) and provide a
clear install hint if missing.

## Schema

The registry file must conform to a JSON Schema shipped with `dctl`. The
schema file lives at:

```text
schemas/projects.schema.yaml
```

Installed to:

```text
~/.local/share/dctl/schemas/projects.schema.yaml
```

### Schema Definition

```yaml
# schemas/projects.schema.yaml
$schema: https://json-schema.org/draft/2020-12/schema
title: dctl project registry
description: Per-project configuration for devcontainerctl
type: object
additionalProperties:
  type: object
  properties:
    devcontainer:
      type: string
      description: >
        Path to a devcontainer.json file. Overrides local file discovery
        and sibling discovery.
    dockerfile:
      type: string
      description: >
        Managed Dockerfile target name (e.g., python-dev) or direct
        filesystem path to a custom Dockerfile. Applies only to
        dctl image build.
    image:
      type: string
      description: >
        Optional image tag override (e.g., devimg/python-dev:latest).
    sibling_discovery:
      type: boolean
      default: true
      description: >
        Whether to attempt work-clone sibling discovery. Set to false
        for repositories whose names contain a dot but are not
        work-clones.
  additionalProperties: false
```

### Validation

`dctl` should validate the registry file against the schema on every read.
Validation uses `yq` to convert YAML to JSON and a lightweight JSON Schema
validator, or `yq` structural checks if a full validator is too heavy for
the host.

Validation strategy (ordered by preference):

1. **`yq` + `check-jsonschema`**: If `check-jsonschema` (Python pip package)
   is available, use it for full schema validation.
2. **`yq` structural checks**: If no schema validator is available, use `yq`
   to verify that all keys are recognized and values have the expected types.
   This is a best-effort fallback, not full schema compliance.

Validation rules:

- Validate on every registry read, not just on write.
- Invalid schema is an error that names the file and the offending key/value.
- Missing file is a normal miss in the resolution chain (not an error).
- Empty file is treated as an empty registry (no projects configured).

## Canonical Name Derivation

All work-clones of the same repository must map to the same canonical project
name.

Derivation order:

1. If the workspace is a git repository with a remote URL, derive the canonical
   name from the remote.
   - `org/repo` becomes `org-repo`
   - `github.com:org/repo.git` becomes `org-repo`
   - `https://github.com/org/repo.git` becomes `org-repo`
2. Fallback to the workspace basename after stripping the work-clone suffix.
   - `repo.42-add-auth` becomes `repo`
   - `repo` stays `repo`

Normalization rules:

- Strip a trailing `.git` from remote-derived repo names.
- Replace `/` with `-`.
- Use the work-clone stripping rule from
  [`00-resolution-model.md`](./00-resolution-model.md) when the basename contains
  a `.`.

## Fields

### `devcontainer`

- Path to a `devcontainer.json`.
- Overrides local file discovery and sibling discovery.
- Ignored if the CLI flag or `DCTL_CONFIG` environment variable is set.

### `dockerfile`

- Either the name of a managed Dockerfile target such as `python-dev`, or a
  direct path to a custom Dockerfile.
- Applies only to `dctl image build`. When set and no explicit CLI target is
  provided, the registry value directs target selection.
- If the value is a managed target name, resolution uses the two-layer hierarchy
  defined in [`40-dockerfile-hierarchy.md`](./40-dockerfile-hierarchy.md).
- If the value is a filesystem path, it is validated directly without going
  through the two-layer lookup.

### `image`

- Optional image tag override, such as `devimg/python-dev:latest`.
- Intended for future code paths that need to select or validate an image based
  on project config.
- Does not replace `devcontainer`; it complements it.

### `sibling_discovery`

- Accepts `true` or `false`.
- Default is `true`.
- Allows opt-out for repositories whose names contain `.` but are not
  work-clones.

## Parsing Model

The registry file is parsed by `yq` in read-only mode. No shell sourcing
is involved.

Recommended patterns:

```bash
# Read a specific field for a project
yq -r ".\"${canonical_name}\".devcontainer // \"\"" \
  "$DCTL_CONFIG_DIR/projects.yaml"

# Check if a project entry exists
yq -e ".\"${canonical_name}\"" \
  "$DCTL_CONFIG_DIR/projects.yaml" >/dev/null 2>&1

# Read sibling_discovery with default
yq -r ".\"${canonical_name}\".sibling_discovery // true" \
  "$DCTL_CONFIG_DIR/projects.yaml"
```

Parsing rules:

- Use `yq` for all reads — never source or eval the file.
- Read only the recognized fields.
- Treat missing file as a normal miss in the resolution chain.
- Treat invalid YAML as an error that points to the file path.
- Treat schema violations as errors that identify the offending key.

## Resolution Behavior

The project registry is third in precedence, after CLI flags and environment
variables and before local project files.

That means:

- A registry entry can override a checked-in local `.devcontainer/devcontainer.json`.
- A developer can still bypass the registry with a CLI flag or environment
  variable.
- Sibling discovery only runs if registry and local file lookup both miss, or if
  the registry provides no `devcontainer` key for the project.

## Security and Trust Model

Because the registry file is parsed by `yq` (not shell-sourced), there is no
arbitrary code execution risk. YAML is data-only.

Guardrails:

- Only read from the expected `~/.config/dctl/projects.yaml` path.
- Never read registry files from the workspace.
- Validate against the schema before consuming values.
- Path values (`devcontainer`, `dockerfile`) are validated for existence
  before use.

## Worked Examples

### Example 1: Shared config across work-clones

```yaml
# ~/.config/dctl/projects.yaml
org-repo:
  devcontainer: /home/alice/.config/dctl/shared/org-repo/devcontainer.json
  sibling_discovery: true
```

- `/home/alice/projects/repo`
- `/home/alice/projects/repo.42-add-auth`
- `/home/alice/projects/repo.43-fix-tests`

All three map to the same canonical project and therefore use the same registry
entry.

### Example 2: Managed image override

```yaml
org-repo:
  dockerfile: agents
  image: devimg/agents:latest
```

This leaves devcontainer config selection to the normal chain but tells future
image-management code to prefer the `agents` managed Dockerfile target.

### Example 3: Disable sibling discovery

```yaml
acme-repo:
  sibling_discovery: false
```

This prevents `repo.docs/` from being treated like a work-clone of `repo/`.

### Example 4: Direct Dockerfile path

```yaml
personal-api:
  dockerfile: /home/alice/custom/Dockerfile
```

This bypasses the two-layer managed lookup entirely and uses the custom
Dockerfile directly.
