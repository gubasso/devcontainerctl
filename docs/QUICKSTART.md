# Devcontainer Quickstart

## Prerequisites

- Docker with `buildx`
- Dev Container CLI installed (`devcontainer`)

## Setup

```bash
make install
cd ~/projects/my-api
dctl deploy devcontainer python
dctl deploy image python-dev
dctl init --devcontainer python
dctl ws up
dctl ws shell
```

## How Composition Works

Each selectable config is defined by a YAML **manifest** that declares an
ordered list of layers to compose. For example, `python.yaml`:

```yaml
layers:
  - base      # shared infrastructure (auth mounts, terminal env, remote user)
  - python    # leaf layer (image tag, cache volumes, bootstrap commands)
```

Each layer name maps to a directory containing a `devcontainer.json`.
`dctl init` reads the manifest, resolves each layer from
`~/.config/dctl/devcontainer/<layer>/devcontainer.json`, and merges them in
order into a single cached `devcontainer.json` consumed by `dctl ws up`.

The **last layer** in the manifest is the **leaf** — it holds your
project-specific settings and is protected from overwrites on deploy. All
preceding layers are **shared** and reconciled automatically.

Manifests are validated against `schemas/compose.schema.yaml` (JSON Schema
Draft 2020-12). The only field is `layers` (non-empty array of strings);
the filename stem is the manifest name.

## Available Configs

| Config | Layers | Image |
| --- | --- | --- |
| `general` | base, general | `devimg/agents:latest` |
| `coordinator` | base, coordinator | `devimg/agents:latest` |
| `python` | base, python | `devimg/python-dev:latest` |
| `rust` | base, rust | `devimg/rust-dev:latest` |
| `zig` | base, zig | `devimg/zig-dev:latest` |

## Creating a Custom Manifest

To compose a custom layer stack, create a manifest in user config:

```yaml
# ~/.config/dctl/devcontainer/myproject.yaml
name: myproject
layers:
  - base
  - dotfiles    # optional personal layer (see examples/dotfiles/)
  - python      # leaf — last layer wins for scalar fields
```

Then add your layer directories under `~/.config/dctl/devcontainer/` and run
`dctl init --devcontainer myproject`.

## Common Commands

```bash
dctl deploy --list
dctl init --devcontainer python
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
