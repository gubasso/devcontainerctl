# Devcontainer Quickstart

## Prerequisites

- openSUSE Tumbleweed with rootless Podman
- `crun` built with `+LIBKRUN`, plus `libkrun` and `libkrunfw`
- `pasta` or `slirp4netns` for rootless networking
- `/dev/kvm` access for your user (`kvm` group on openSUSE)
- Run `dctl doctor` before the first workspace start to verify the host

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

See [INSTALL.md](INSTALL.md) for the package, networking, and KVM setup details.

## How Composition Works

Each selectable config is defined by a YAML **manifest** that declares an
ordered list of layers to compose. For example, `python.yaml`:

```yaml
layers:
  - base      # shared infrastructure (auth mounts, terminal env, remote user)
  - agents    # shared agents layer (bubblewrap-friendly seccomp profile, agent CLI mounts)
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
Draft 2020-12). `layers` is required, and optional `runtime` / `network`
policy keys can be added at the manifest root when needed. The filename stem
is the manifest name.

## Available Configs

| Config | Layers | Image |
| --- | --- | --- |
| `general` | base, agents, general | `devimg/agents:latest` |
| `coordinator` | base, agents, coordinator | `devimg/agents:latest` |
| `python` | base, agents, python | `devimg/python-dev:latest` |
| `rust` | base, agents, rust | `devimg/rust-dev:latest` |
| `zig` | base, agents, zig | `devimg/zig-dev:latest` |

## Creating a Custom Manifest

To compose a custom layer stack, create a manifest in user config:

```yaml
# ~/.config/dctl/devcontainer/myproject.yaml
layers:
  - base
  - agents      # include if you want the bundled seccomp profile + agent mounts
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

See [README.md](../README.md), [ARCHITECTURE.md](ARCHITECTURE.md), and [INSTALL.md](INSTALL.md).
