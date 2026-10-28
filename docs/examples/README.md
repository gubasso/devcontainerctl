# Examples of a dctl configuration

dctl is agnostic. It composes, builds, and runs devcontainers from the configuration in `~/.config/dctl/`, and ships no image, no layer, and no manifest. You write that folder: by hand, with a dotfiles manager, or with home-manager. dctl installs, activates, and names no dev environment manager.

This folder holds a small, working configuration to copy from, for a person or a coding agent. No dctl command reads it, and `make install` does not install it.

## What each example shows

`config/dctl/` has the layout of `~/.config/dctl/`:

| Path | What it shows |
| --- | --- |
| `images/example/Dockerfile` | A user image: a plain distribution image and the user account, with commented placeholders for the tools that you choose. `dctl image build example` tags it `devimg/example:latest`. |
| `devcontainer/example.yaml` | A manifest: the layers in composition order. The last layer is the leaf. |
| `devcontainer/base/devcontainer.json` | A shared layer: the remote user, the terminal variables, and the auth mounts. |
| `devcontainer/agents/` | A shared layer for AI coding agents: the config mounts of the agent CLIs, and the seccomp profile `seccomp-bwrap.json` that lets bubblewrap run. |
| `devcontainer/dotfiles/devcontainer.json` | An optional layer that binds a dotfiles checkout from `$DOTFILES`. `example.yaml` does not list it: add it after you set `DOTFILES`. |
| `devcontainer/example/devcontainer.json` | The leaf: it names the image and runs no lifecycle command. |
| `projects.yaml` | The shape of the project registry that `dctl init` writes. |

## Copy them

1. Copy the examples:

   ```bash
   mkdir -p ~/.config/dctl
   cp -r docs/examples/config/dctl/images docs/examples/config/dctl/devcontainer ~/.config/dctl/
   ```

2. Edit the copies before the first build. Every bind source of a layer must exist on the host, or `dctl init` and `dctl ws up` stop with a missing path. The `base` layer binds `~/.gitconfig`, and the `agents` layer binds `~/.claude`, `~/.claude.json`, `~/.codex`, and `~/.gemini`: remove the mounts of the agents that you do not use. To use the `dotfiles` layer, set `DOTFILES` to your checkout and add `dotfiles` to `example.yaml` before `example`. Install in the image what your projects need, and rename `example` to a name that fits.

3. Build the image and register a project:

   ```bash
   dctl image build example
   cd ~/Projects/your-project && dctl init --devcontainer example
   ```

## Your image carries your tools

Each project owns its dev environment: its configuration files, and the guidance in its own `AGENTS.md` or `README.md` about how to run a command in it. You make sure that the image carries what your projects need. A command shell from `dctl ws run` or `dctl ws shell <cmd>` gets no project environment from dctl, so a project tool runs through the native command of the project's manager, for example `dctl ws run -- direnv exec . make check`.

Tools that activate a project environment when you enter its folder:

| Tool | Upstream | Run one command in the environment |
| --- | --- | --- |
| direnv | <https://direnv.net> | `direnv exec DIR CMD` |
| mise (`mise activate`) | <https://mise.jdx.dev> | `mise exec -- CMD` |
| shadowenv | <https://shopify.github.io/shadowenv/> | `shadowenv exec -- CMD` |
| autoenv | <https://github.com/hyperupcall/autoenv> | none |
| quickenv | <https://codeberg.org/untitaker/quickenv> | `quickenv exec -- CMD` |
| Environment Modules | <https://envmodules.io> | `module load NAME`, then CMD in the same shell |

Tools that set up a project environment:

| Tool | Upstream | Run one command in the environment |
| --- | --- | --- |
| Nix flakes | <https://nix.dev/manual/nix/latest/command-ref/new-cli/nix3-develop> | `nix develop --command CMD` |
| nix-direnv | <https://github.com/nix-community/nix-direnv> | through direnv: `direnv exec . CMD` |
| devenv | <https://devenv.sh> | `devenv shell -- CMD` |
| devbox | <https://www.jetify.com/devbox> | `devbox run CMD` |
| flox | <https://flox.dev> | `flox activate -- CMD` |
| mise | <https://mise.jdx.dev> | `mise exec -- CMD` |
| asdf | <https://asdf-vm.com> | `asdf exec CMD` |
| pixi | <https://pixi.sh> | `pixi run CMD` |
| aqua | <https://aquaproj.github.io> | `aqua exec -- CMD` |
| proto | <https://moonrepo.dev/proto> | `proto exec TOOL -- CMD` |
| Hermit | <https://cashapp.github.io/hermit> | `./bin/CMD` from the project root |
| pkgx | <https://pkgx.sh> | `pkgx +PKG -- CMD` |

The upstream pages were checked on 2026-10-28. Two more tools exist: zsh-autoenv (<https://github.com/Tarrasch/zsh-autoenv>), whose last commit is of 2024-06-04, and lorri (<https://github.com/nix-community/lorri>), whose 2.0.0 rewrite of 2026-04-28 adds a shell hook and has no command that runs one command in the environment.
