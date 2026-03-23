# Shared Resolution Model

## Purpose

This document defines the unified config resolution model for future `dctl`
behavior. It applies to both `devcontainer.json` selection and Dockerfile
selection. Command-specific details are defined in later specs, but they must
conform to the ordering and invariants in this document.

## Goals

- Support work-clone workflows without duplicating `.devcontainer/devcontainer.json`
  across sibling clones.
- Allow explicit user overrides from the CLI and environment.
- Add host-side project configuration without breaking current local-project
  behavior.
- Preserve the current split between user config and installed data assets.
- Keep resolution behavior debuggable and deterministic.

## Devcontainer.json Precedence

The following precedence chain applies to `devcontainer.json` resolution.
Highest wins.

1. Explicit CLI flag — `dctl --config <path>`
2. Environment variable — `DCTL_CONFIG`
3. Per-project registry entry — `devcontainer` key in
   `~/.config/dctl/projects.yaml`
4. Local project file — `.devcontainer/devcontainer.json`
5. Work-clone sibling discovery
6. User global default — `~/.config/dctl/default/devcontainer.json`

Dockerfile resolution uses a separate, narrower model scoped to
`dctl image build`. See the
[Dockerfile Resolution Scope](#dockerfile-resolution-scope) section below.

The precedence order is intentionally explicit-first and fallback-last. This
means the user can override any automatic discovery path, and a host-side
project registry can redirect a project away from local checked-in files when
needed.

## XDG Layout

The design formalizes the following split:

- `~/.config/dctl/`
  - User-controlled config
  - Project registry (`projects.yaml`)
  - User defaults
  - User-defined templates
  - User-overridden managed image Dockerfiles
- `~/.local/share/dctl/`
  - Installed data shipped by the project
  - Built-in templates
  - Managed image Dockerfiles

Future implementation should honor XDG variables:

- `${XDG_CONFIG_HOME:-$HOME/.config}/dctl`
- `${XDG_DATA_HOME:-$HOME/.local/share}/dctl`

## Path Normalization

All filesystem paths participating in comparison or selection must be normalized
with `realpath` before comparison.

Required rules:

- Normalize `WORKSPACE_FOLDER` before deriving sibling candidates.
- Normalize explicit CLI paths, environment paths, registry paths, and discovered
  paths before use.
- Compare normalized paths to prevent a symlinked path from appearing different
  from its physical path.
- Preserve the original path string only for user-facing logging if needed; all
  internal comparisons should use the normalized form.

## Resolution Logging

`dctl` should emit a normal `log`-level message whenever it selects a config
source. The goal is to make resolution explainable without adding a separate
debug mode.

Examples:

- `Using devcontainer config from CLI flag: /path/to/devcontainer.json`
- `Using devcontainer config from project registry: org-repo in ~/.config/dctl/projects.yaml`
- `Using Dockerfile override from ~/.config/dctl/images/agents/Dockerfile`

Logging rules:

- Log only the winning source, not every miss in the chain.
- Include enough context to tell whether the source came from CLI, env, registry,
  local file, sibling discovery, or user default.
- If resolution fails, include the final relevant path or source category in the
  error message.

## Devcontainer CLI Integration

`dctl` resolves the effective `devcontainer.json` path before it invokes the
Dev Container CLI. Once resolved, `dctl` should pass the result through to
`devcontainer up` using the Dev Container CLI's `--config <resolved-path>` flag.

This design has two important invariants:

- `--workspace-folder` remains the current workspace directory.
- Container identity and mount resolution continue to be based on the workspace
  directory, not on the resolved config file location.

That means a work-clone using a sibling repo's config still gets its own
container identity and its own `${localWorkspaceFolderBasename}` value.

## Work-Clone Sibling Discovery

The shared sibling discovery algorithm is:

```text
workspace_basename = basename(WORKSPACE_FOLDER)
if workspace_basename contains '.':
    main_repo_name = workspace_basename split on first '.' -> take first part
    parent_dir = dirname(WORKSPACE_FOLDER)
    candidate = parent_dir / main_repo_name
    if candidate exists AND candidate != WORKSPACE_FOLDER:
        if candidate/.devcontainer/devcontainer.json exists:
            use candidate's config
```

## Sibling Discovery Guards

The algorithm must apply these guards:

- The candidate directory must exist.
- The candidate directory must not be the same path as `WORKSPACE_FOLDER` after
  normalization.
- The candidate must be a git repository by containing `.git/`.
- The candidate config must exist at the expected local-project path for the
  relevant artifact.
- Sibling discovery is skipped if project registry sets
  `sibling_discovery: false`.

The git-repository guard exists to avoid false matches for sibling directories
that happen to share the same basename prefix.

## Dockerfile Resolution Scope

Dockerfile resolution applies only to the `dctl image build` command. Unlike
`devcontainer.json` resolution — which is a cross-command concern affecting
`ws up`, `ws reup`, and `test` — Dockerfile resolution is scoped to the image
build flow.

The applicable precedence for `dctl image build <target>` is:

1. User custom Dockerfile: `~/.config/dctl/images/<target>/Dockerfile`
2. Installed managed Dockerfile: `~/.local/share/dctl/images/<target>/Dockerfile`

The broader precedence chain (CLI flag, env var, sibling discovery, user global
default) does not apply to Dockerfiles because Dockerfiles are selected by
target name, not by workspace context. The project registry `DOCKERFILE` field
can either redirect a managed target name (which then goes through the
two-layer lookup above) or provide a direct filesystem path (which is validated
directly without the two-layer lookup).

See [`40-dockerfile-hierarchy.md`](./40-dockerfile-hierarchy.md) for details.

## Error Handling

Resolution must fail early when an explicit source is invalid.

Rules:

- If the CLI flag points to a missing path, error immediately.
- If the environment variable points to a missing path, error immediately.
- If the project registry entry exists but points to a missing path, error and
  identify the project name and registry file.
- If the chain exhausts all sources with no result, return a command-specific
  error such as `run 'dctl init'`.

## Non-Goals

- This spec does not change how `dctl ws exec`, `dctl ws shell`, or `dctl ws run`
  locate containers after they are running.
- This spec does not require `dctl init` to write non-local configs.
- This spec does not collapse multiple work-clones into a shared container.
