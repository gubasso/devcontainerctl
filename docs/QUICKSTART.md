# Devcontainer Quickstart

## Prerequisites

- Docker with `buildx`
- Dev Container CLI installed (`devcontainer`)

## Setup

dctl ships no image, no layer, and no manifest. It reads `~/.config/dctl/`, and
you write it: by hand, with a dotfiles manager, or with home-manager.
[examples/](examples/README.md) holds a copyable starting point in that layout.
Edit the copies before `dctl init`: every bind source of a layer must exist on
the host ([examples/](examples/README.md#copy-them)).

```bash
make install
mkdir -p ~/.config/dctl
cp -r docs/examples/config/dctl/images docs/examples/config/dctl/devcontainer ~/.config/dctl/
$EDITOR ~/.config/dctl/devcontainer/agents/devcontainer.json   # keep only the mounts whose host paths exist
cd ~/projects/my-api
dctl init --devcontainer example
dctl ws up
dctl ws shell
```

## How Composition Works

Each selectable config is defined by a YAML **manifest** that declares an
ordered list of layers to compose. For example, `example.yaml`:

```yaml
layers:
  - base      # shared infrastructure (auth mounts, terminal env, remote user)
  - agents    # shared agents layer (bubblewrap-friendly seccomp profile, agent CLI mounts)
  - example   # leaf layer (image tag, cache volumes)
```

Each layer name maps to a directory containing a `devcontainer.json`.
`dctl init` registers the manifest for the project; the merge runs on demand.
On each command that needs it, `dctl` reads the manifest, resolves each layer
from `~/.config/dctl/devcontainer/<layer>/devcontainer.json`, and merges them in
order into a single `devcontainer.json` regenerated fresh under
`$XDG_RUNTIME_DIR/dctl/devcontainer/<name>/` (never cached) and consumed by
`dctl ws up`/`reup`/`test`. Manifest-backed commands require `jq`.

The **last layer** in the manifest is the **leaf** — it holds your
project-specific settings. All preceding layers are **shared**: several
manifests can list the same layer.

Manifests are validated against `schemas/compose.schema.yaml` (JSON Schema
Draft 2020-12). The only field is `layers` (non-empty array of strings);
the filename stem is the manifest name.

## Available Configs

The configs are the manifests in `~/.config/dctl/devcontainer/`, and the names
are yours. The examples define one:

| Config | Layers | Image |
| --- | --- | --- |
| `example` | base, agents, example | `devimg/example:latest` |

Each image installs what your projects need; each project owns its own dev
environment setup.

## Creating a Custom Manifest

To compose a custom layer stack, create a manifest in user config:

```yaml
# ~/.config/dctl/devcontainer/myproject.yaml
layers:
  - base
  - agents      # include if you want the seccomp profile + agent mounts of the examples
  - dotfiles    # optional personal layer (see examples/)
  - myproject   # leaf — last layer wins for scalar fields
```

Then add your layer directories under `~/.config/dctl/devcontainer/` and run
`dctl init --devcontainer myproject`.

## Common Commands

```bash
dctl init --devcontainer example
dctl ws up
dctl ws reup
dctl ws shell
dctl ws shell claude
dctl ws exec -- pytest
dctl ws status
dctl ws down
dctl image build --all
dctl test
```

## Full Documentation

See [README.md](../README.md) and [ARCHITECTURE.md](ARCHITECTURE.md).
