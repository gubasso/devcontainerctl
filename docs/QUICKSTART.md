# Devcontainer Quickstart

## Prerequisites

- Docker with `buildx`
- Dev Container CLI installed (`devcontainer`)
- Dotfiles repo at `~/.dotfiles` or `DOTFILES=/path/to/dotfiles`
- Managed images built: `dctl image build --all`

## Setup

```bash
make install
cd ~/projects/my-api
dctl init --template python
dctl ws up
dctl ws shell
```

Shared settings come from the `_base` template, merged automatically by `dctl init`.

## Available Templates

| Template | Use case |
| --- | --- |
| `general` | Minimal general-purpose sandbox on `devimg/agents:latest` |
| `coordinator` | Coordinator workflow with sibling-repo visibility |
| `python` | Python projects on `devimg/python-dev:latest` |
| `rust` | Rust projects on `devimg/rust-dev:latest` |
| `zig` | Zig projects on `devimg/zig-dev:latest` |

## Common Commands

```bash
dctl init --list
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
