# Devcontainer Templates

Reusable project templates live here for versioned tracking in this repo.

- `python/devcontainer.json`: baseline Python project config using `devimg/python-dev:latest`
- `rust/devcontainer.json`: baseline Rust project config using `devimg/rust-dev:latest`
- `zig/devcontainer.json`: baseline Zig project config using `devimg/zig-dev:latest`

These files are scaffolding sources. `dctl init` deploys them to
`~/.config/dctl/devcontainer/<name>/devcontainer.json` and registers the
deployed path for runtime use.

The dotfiles bootstrap runs automatically from the bind-mounted dotfiles repo
via the `devimg/agents` `devcontainer.metadata` label — projects do not need
their own copy of the setup script.

Templates contain only project-specific deltas. Shared mounts, the dotfiles
bootstrap hook, and baseline container settings are inherited from the
`devimg/agents` image via its `devcontainer.metadata` label.
