# Workflow Comparison: Podman vs Dev Containers vs dctl

## The scenario

Ana is building multiple AI-agent-friendly dev workspaces. She wants one
repeatable image authoring surface, one declarative runtime config, and one
command set that stays aligned across projects and teammates.

This comparison focuses on three ways to run that workflow today:

- raw Podman commands
- the Dev Container CLI
- `dctl`

## TL;DR

| Task | `dctl` | Dev Container CLI | Raw Podman |
| --- | --- | --- | --- |
| Set up a new Python workspace | `dctl deploy devcontainer python && dctl deploy image python-dev && dctl init --devcontainer python` | Write a `Containerfile` + `.devcontainer/devcontainer.json` manually | Write a `Containerfile` and run `podman build` / `podman run` manually |
| Start the workspace | `dctl ws up` | `devcontainer up --workspace-folder . --config /path/to/devcontainer.json` | `podman run ...` |
| Open a shell | `dctl ws shell` | `devcontainer exec --workspace-folder . bash` | `podman exec -it <container> bash` |
| Run a command | `dctl ws exec -- pytest` | `devcontainer exec --workspace-folder . pytest` | `podman exec -it <container> pytest` |
| Rebuild managed base images | `dctl image build --all` | No built-in global image build flow | Rebuild each image explicitly with `podman build` |
| Stop and remove the workspace | `dctl ws down` | No single built-in command | `podman rm -f <container>` |

## Raw Podman

Raw Podman keeps the stack explicit. Ana authors a `Containerfile`, builds an
image, then owns the entire `podman run` argv: mounts, env, keepalive command,
and any post-create bootstrap.

```bash
podman build -t snackbar-api-dev:latest .
podman run -d --name snackbar-api-dev ...
podman exec -it snackbar-api-dev bash -lc "pre-commit install"
```

This is the lowest-level, least opinionated option. It is also the most
repetitive once multiple projects need the same image shape, token forwarding,
or workspace-specific bootstrap.

## Dev Container CLI

The Dev Container CLI moves the runtime config into `devcontainer.json` and
gives Ana real lifecycle hooks such as `postCreateCommand`. It still leaves the
image authoring problem in place: each repo carries its own `Containerfile`
plus its own devcontainer config.

Set `build.dockerfile` to `Containerfile`, keep the build context next to the
repo config, and use `postCreateCommand` for workspace-dependent bootstrap such
as `pre-commit install`.

The result is more declarative than raw Podman, but cross-project sharing is
still manual unless the team builds its own template system around it.

## dctl

`dctl` keeps the upstream devcontainer surface but standardizes the shared
parts:

- managed `Containerfile`s under `~/.config/dctl/images/`
- manifest-driven layer composition under `~/.config/dctl/devcontainer/`
- cached merged output under `~/.cache/dctl/devcontainer/`
- Podman/libkrun runtime defaults handled by the tool instead of by hand

```bash
dctl deploy devcontainer python
dctl deploy image python-dev
dctl init --devcontainer python
dctl ws up
```

For Ana, the main gain is not fewer concepts. It is fewer places where those
concepts must be repeated.

## Where each approach fits

| Use case | Best fit | Why |
| --- | --- | --- |
| One-off local experiment | Raw Podman | Fastest path when no sharing or lifecycle layering matters |
| Repo-native devcontainer workflow | Dev Container CLI | Best when the repo should own its own `.devcontainer/` config directly |
| Shared image + shared config across many repos | `dctl` | Centralizes Containerfiles, merge logic, runtime defaults, and workspace identity |

## Bottom line

Raw Podman is the clean low-level controller. The Dev Container CLI is a
useful declarative wrapper around that controller. `dctl` adds a shared
Containerfile catalog, manifest composition, workspace-aware container
selection, and Podman/libkrun defaults on top.
