# Per-Project Registry

## Purpose

This document defines the host-side per-project registry used by `dctl` to
inject project-specific config without requiring every work-clone to carry its
own local `.devcontainer` files.

## Location

Project registry entries live at:

```text
~/.config/dctl/projects/<canonical-name>.conf
```

The design must honor `${XDG_CONFIG_HOME:-$HOME/.config}/dctl/projects/` in
future implementation.

## Format

The format is shell-parseable `key=value` in `.env` style. The design chooses
this format so a Bash implementation can parse it without adding a JSON, TOML,
or YAML parser dependency on the host.

Example:

```bash
# ~/.config/dctl/projects/myrepo.conf
DEVCONTAINER_CONFIG=/path/to/devcontainer.json
DOCKERFILE=python-dev
IMAGE=devimg/python-dev:latest
SIBLING_DISCOVERY=true
```

Format rules:

- One assignment per line.
- Comments start with `#`.
- Values should be quoted if they contain spaces.
- Unknown keys are ignored by the initial implementation.
- Invalid shell syntax is treated as a config error.

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

### `DEVCONTAINER_CONFIG`

- Path to a `devcontainer.json`.
- Overrides local file discovery and sibling discovery.
- Ignored if the CLI flag or `DCTL_CONFIG` environment variable is set.

### `DOCKERFILE`

- Either the name of a managed Dockerfile target such as `python-dev`, or a
  direct path to a custom Dockerfile.
- Applies only to `dctl image build`. When set and no explicit CLI target is
  provided, the registry value directs target selection.
- If the value is a managed target name, resolution uses the two-layer hierarchy
  defined in [`40-dockerfile-hierarchy.md`](./40-dockerfile-hierarchy.md).
- If the value is a filesystem path, it is validated directly without going
  through the two-layer lookup.

### `IMAGE`

- Optional image tag override, such as `devimg/python-dev:latest`.
- Intended for future code paths that need to select or validate an image based
  on project config.
- Does not replace `DEVCONTAINER_CONFIG`; it complements it.

### `SIBLING_DISCOVERY`

- Accepts `true` or `false`.
- Default is `true`.
- Allows opt-out for repositories whose names contain `.` but are not
  work-clones.

## Parsing Model

The registry file should be parsed by sourcing it inside a subshell so the
parent shell environment is not polluted.

Recommended pattern:

```bash
(
  set -a
  # shellcheck disable=SC1090
  source "$registry_file"
  printf '%s\n' "$DEVCONTAINER_CONFIG"
)
```

Parsing rules:

- Source in a subshell or equivalent isolated scope.
- Read only the recognized variables.
- Treat missing files as a normal miss in the resolution chain.
- Treat invalid syntax as an error that points to the registry file path.

## Resolution Behavior

The project registry is third in precedence, after CLI flags and environment
variables and before local project files.

That means:

- A registry entry can override a checked-in local `.devcontainer/devcontainer.json`.
- A developer can still bypass the registry with a CLI flag or environment
  variable.
- Sibling discovery only runs if registry and local file lookup both miss, or if
  the registry provides no relevant key.

## Security and Trust Model

Because `.conf` files are sourced by a shell implementation, they must be
treated as trusted user config. This is acceptable because they live in the
user's own config directory.

Guardrails:

- Only source files from the expected `~/.config/dctl/projects/` directory.
- Do not source registry files from the workspace.
- Document that malformed or malicious shell in the registry file is equivalent
  to arbitrary code execution under the user's account.

## Worked Examples

### Example 1: Shared config across work-clones

```bash
# ~/.config/dctl/projects/org-repo.conf
DEVCONTAINER_CONFIG=/home/alice/.config/dctl/shared/org-repo/devcontainer.json
SIBLING_DISCOVERY=true
```

- `/home/alice/projects/repo`
- `/home/alice/projects/repo.42-add-auth`
- `/home/alice/projects/repo.43-fix-tests`

All three map to the same canonical project and therefore use the same registry
entry.

### Example 2: Managed image override

```bash
# ~/.config/dctl/projects/org-repo.conf
DOCKERFILE=agents
IMAGE=devimg/agents:latest
```

This leaves devcontainer config selection to the normal chain but tells future
image-management code to prefer the `agents` managed Dockerfile target.

### Example 3: Disable sibling discovery

```bash
# ~/.config/dctl/projects/acme-repo.conf
SIBLING_DISCOVERY=false
```

This prevents `repo.docs/` from being treated like a work-clone of `repo/`.
