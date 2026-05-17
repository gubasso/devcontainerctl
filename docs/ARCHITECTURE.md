# Architecture

`dctl` is a Podman-first devcontainer workflow with a libkrun-backed microVM
runtime on Linux. The user-facing authoring surface stays familiar:

- image definitions live under `images/<name>/Containerfile`
- config layers live under `devcontainers/<layer>/devcontainer.json`
- manifests compose those layers through `schemas/compose.schema.yaml`

The runtime adapter and lifecycle interpreter live in the shell tree:

- `lib/dctl/runtime/{common,krun}.sh`
- `lib/dctl/lifecycle.sh`

## Reproducibility model

| Layer | Strategy | Source of truth |
| --- | --- | --- |
| Base images | Rolling, rebuilt regularly | `images/*/Containerfile` |
| Devcontainer config | Declarative, layered | `devcontainers/` + manifests |
| Python version | Project-pinned | `pyproject.toml` |
| Rust toolchain | Project-pinned | `rust-toolchain.toml` |
| Zig version | Project-pinned | `build.zig.zon` |

Shared image layers stay reusable, while project-specific runtime versions stay
declared in the project itself.

## Implemented feature set

The current codebase implements the spec set under [spec/](../spec/README.md):

- manifest-driven layer composition with cache output under `~/.cache/dctl/`
- per-project registry selection in `~/.config/dctl/projects.yaml`
- managed image deployment into `~/.config/dctl/images/`
- user-config-only Containerfile resolution for `dctl image build`
- Podman/libkrun runtime execution with `dctl`-owned lifecycle handling
- default-deny egress plus scoped credential forwarding

## Directory layout

```text
~/.local/share/dctl/
├── images/
│   ├── agents/Containerfile
│   ├── python-dev/Containerfile
│   ├── rust-dev/Containerfile
│   └── zig-dev/Containerfile
├── devcontainers/
│   ├── base/devcontainer.json
│   ├── agents/devcontainer.json
│   ├── python/devcontainer.json
│   └── python.yaml
└── schemas/
    └── compose.schema.yaml

~/.config/dctl/
├── images/
│   └── python-dev/Containerfile
├── devcontainer/
│   ├── base/devcontainer.json
│   ├── python/devcontainer.json
│   └── python.yaml
└── projects.yaml

~/.cache/dctl/
└── devcontainer/
    └── python/devcontainer.json
```

Installed files are seed sources only. Runtime operations read only from user
config and cache.

## Image strategy

The managed image stack is layered:

```text
devimg/agents:latest
  ├── devimg/python-dev:latest
  ├── devimg/rust-dev:latest
  └── devimg/zig-dev:latest
```

The source of truth for those images is the repository `Containerfile` set:

- [images/agents/Containerfile](../images/agents/Containerfile)
- [images/python-dev/Containerfile](../images/python-dev/Containerfile)
- [images/rust-dev/Containerfile](../images/rust-dev/Containerfile)
- [images/zig-dev/Containerfile](../images/zig-dev/Containerfile)

Build them through `dctl`:

```bash
dctl image build --all
```

Or directly with Podman when debugging image layers:

```bash
cd ~/.config/dctl/images
podman build --build-arg USERNAME=$USER --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) -t devimg/agents:latest ./agents
podman build --build-arg USERNAME=$USER --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) -t devimg/python-dev:latest ./python-dev
podman build --build-arg USERNAME=$USER --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) -t devimg/rust-dev:latest ./rust-dev
podman build --build-arg USERNAME=$USER --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) -t devimg/zig-dev:latest ./zig-dev
```

## Config composition

Each selectable configuration is a manifest with a required `layers` array and
optional `runtime` / `network` metadata:

```yaml
layers:
  - base
  - agents
  - python
runtime:
  name: krun
  resources:
    memory_mib: 4096
    cpus: 2
network:
  allow:
    - api.anthropic.com
```

Merge behavior:

- scalars are last-wins
- `mounts` concatenate
- `postCreateCommand` merges by key
- `containerEnv` and `remoteEnv` merge by key
- `runArgs`, `workspaceMount`, and `workspaceFolder` are first-class merge keys

The resulting cache file is what `dctl ws up` and related commands consume.

## Runtime model

On Linux, `dctl` shells out to Podman and selects the `krun` runtime through
the runtime adapter. The container boundary is a microVM rather than a shared
host kernel namespace boundary.

Key implications:

- every runtime operation goes through `podman`
- `dctl` interprets the devcontainer lifecycle keys itself
- default egress is allowlisted
- long-lived host credential directories are not live-mounted

## Security posture

Default path:

- `--cap-drop=ALL`
- `--security-opt no-new-privileges`
- `/tmp` as tmpfs
- egress allowlist enforced in-guest
- permissive seccomp/AppArmor behavior isolated to `agents-permissive`

The permissive `seccomp-bwrap.json` profile remains an opt-in asset for nested
`bwrap` workflows; the default `agents` layer is the stricter path.

See [SECURITY.md](./SECURITY.md) for the operational details and
[docs/specs/sandbox-runtime/SPEC.md](./specs/sandbox-runtime/SPEC.md) for the
threat-model rationale.

## Common workflow

```bash
make install
dctl deploy devcontainer python
dctl deploy image python-dev
dctl init --devcontainer python
dctl ws up
dctl ws shell
```

The main lifecycle commands are:

```bash
dctl ws up
dctl ws reup
dctl ws shell
dctl ws exec -- pytest
dctl ws down
dctl image build --all
dctl doctor
```

## Advanced customization

If a project owns its own image build, set `build.dockerfile` to
`Containerfile` in the local `devcontainer.json` and keep the file beside the
project build context.

For `dctl`-managed images, prefer editing the deployed user copy under
`~/.config/dctl/images/<name>/Containerfile` and rebuilding through
`dctl image build`.

## Related documents

- [README.md](../README.md)
- [QUICKSTART.md](./QUICKSTART.md)
- [INSTALL.md](./INSTALL.md)
- [SECURITY.md](./SECURITY.md)
- [spec/README.md](../spec/README.md)
