# Devcontainer Composition

Reusable layer directories and YAML composition manifests live here for
versioned tracking in this repo.

## Three-Tier Flow

```text
devcontainers/  ──make install──>  ~/.local/share/dctl/devcontainers/
                                  │
                                  └──dctl deploy──>  ~/.config/dctl/devcontainer/
                                                             │
                                                             └──merge manifest-declared layers──>  ~/.cache/dctl/devcontainer/
```

- **Installed** (`~/.local/share/dctl/devcontainers/`): built-in manifests and layers shipped by `make install`
- **Config** (`~/.config/dctl/devcontainer/`): deployed config files, then user-editable
- **Cache** (`~/.cache/dctl/devcontainer/`): generated merged `devcontainer.json` output consumed by `dctl ws up`

## Installed Files Are Seed Sources Only

Installed files under `~/.local/share/dctl/` are never used directly at runtime.
`dctl deploy devcontainer <name>` copies the manifest and referenced layer files
into user config, and `dctl deploy image <name>` copies the associated managed image
files into user config:

- `~/.config/dctl/devcontainer/` — deployed manifests plus layer directories (each may contain `devcontainer.json` and any sibling assets such as a seccomp profile)
- `~/.config/dctl/images/` — managed Containerfile and helper scripts

User config (`~/.config/dctl/`) is the sole runtime source for all operations:
`dctl image build`, `dctl ws up`, `dctl test`. Users can edit these files freely
to customize their setup.

## Manifest Format

Each selectable config is defined by a YAML manifest. A manifest declares the
ordered list of layers to compose into a single `devcontainer.json`:

```yaml
# python.yaml
layers:
  - base      # shared layer — reconciled (overwritten) on every deploy
  - agents    # shared layer — reconciled on every deploy (seccomp + agent CLI mounts)
  - python    # leaf layer — created on first deploy, then user-protected
```

**Fields** (validated by `schemas/compose.schema.yaml`):

| Field | Required | Description |
| --- | --- | --- |
| `layers` | yes | Non-empty array of layer directory names, merged in order |
| `runtime` | no | Optional runtime policy object (`name`, `resources`) for schema-level pinning |
| `network.allow` | no | Optional manifest allowlist metadata merged into the cached config |

No additional properties are allowed. The filename stem is the manifest name.

**Leaf vs shared layers:**

- The **last** layer in `layers` is the **leaf** — it holds project-specific
  settings (image tag, cache volumes, bootstrap commands) and is protected from
  overwrites on deploy (use `--reset` to force).
- All preceding layers are **shared** — they provide common infrastructure and
  are always reconciled (overwritten) from installed sources on deploy.

## Shipped Manifests and Layers

### Layer directories

| Directory | Role | Content |
| --- | --- | --- |
| `base/` | Shared foundation | Remote user, auth mounts, terminal env |
| `agents/` | Shared agents layer | Bubblewrap-friendly security profile (custom seccomp + AppArmor/systempaths off) and agent CLI config mounts (Claude Code, Codex, Gemini) |
| `general/` | Leaf for general | Minimal sandbox on `devimg/agents:latest` |
| `coordinator/` | Leaf for coordinator | Read-only parent-area mount for sibling repos |
| `python/` | Leaf for python | Poetry cache volume, pre-commit bootstrap |
| `rust/` | Leaf for rust | Rust cache volumes, `cargo build` bootstrap |
| `zig/` | Leaf for zig | Zig/ZLS cache volumes, `zig-zls-init` bootstrap |

### Manifests

| Manifest | Layers |
| --- | --- |
| `general.yaml` | `[base, agents, general]` |
| `coordinator.yaml` | `[base, agents, coordinator]` |
| `python.yaml` | `[base, agents, python]` |
| `rust.yaml` | `[base, agents, rust]` |
| `zig.yaml` | `[base, agents, zig]` |

A layer directory without a manifest (e.g. `base/`) is not selectable — it can
only appear as a shared layer referenced by another manifest.

## Merge Semantics

`dctl init` reads a deployed manifest and merges its listed layers in order
using `jq`:

- `mounts` arrays are concatenated in layer order
- `postCreateCommand` objects are merged by key (later layers win)
- `containerEnv` and `remoteEnv` objects are merged by key (later layers win)
- `runArgs` arrays are merged with the round-10 first-class merge logic
- `workspaceMount` and `workspaceFolder` are treated as first-class scalar overrides
- scalar fields use last-wins behavior (the leaf layer overrides earlier values)

## Discovery Rules

- Selectable entries are manifest files (`*.yaml`) — one manifest = one selectable config
- Manifest-referenced non-leaf layers are managed shared layers (reconciled on deploy)
- The last manifest layer is the user-protected leaf layer (skip-if-exists on deploy)
- User customization happens in `~/.config/dctl/devcontainer/`; those user config files are the only merge inputs
- Layer directories without a corresponding manifest are not listed by `dctl deploy --list` or offered by `dctl init`
