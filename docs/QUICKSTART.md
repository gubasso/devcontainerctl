# Devcontainer Quickstart

## Prerequisites

- Docker + buildx running (`docker buildx version` to verify)
- `devcontainer` CLI installed: `bun install -g @devcontainers/cli`
- Images built: `dctl image build --all`

## Setup

1. Run `dctl init --template <python|rust|zig>` in your project root.
2. Add only project-specific mounts or cache volumes as needed.
3. Start: `dctl workspace up`
4. Attach: `dctl workspace shell`
5. Re-run validation any time with `dctl test`

## Template

```jsonc
{
  "name": "<project-name>",
  "image": "devimg/agents:latest",
  "mounts": [
    // Project-specific SSH known_hosts
    // "source=${localEnv:HOME}/.ssh/known_hosts,target=/home/${localEnv:USER}/.ssh/known_hosts,type=bind,readonly"

    // Python caches (for python-dev image)
    // "source=poetry-cache,target=/home/${localEnv:USER}/.cache/pypoetry,type=volume"
  ]
}
```

Shared auth/editor mounts, `remoteUser`, `init`, `shutdownAction`, container env, and the dotfiles `postCreateCommand` come from the `devimg/agents` `devcontainer.metadata` label.

## Available Images

| Image | Use case |
| --- | --- |
| `devimg/agents:latest` | General-purpose (Bun, mise, Claude Code, Codex, OpenCode, Gemini CLI) |
| `devimg/python-dev:latest` | Python projects |
| `devimg/rust-dev:latest` | Rust projects |
| `devimg/zig-dev:latest` | Zig projects |

## Common Commands

```bash
dctl workspace up             # start
dctl workspace reup           # recreate after devcontainer.json/image changes
dctl workspace shell          # attach shell
dctl workspace run -- claude-session  # run agent command
dctl workspace run -- pytest  # execute arbitrary command
dctl workspace status         # show container(s) for current workspace
dctl workspace down           # stop/remove current workspace container(s)
dctl image build --all        # rebuild base images
```

## Full Documentation

See [ARCHITECTURE.md](ARCHITECTURE.md).
