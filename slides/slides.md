---
theme: seriph
title: dctl Sandbox Runtime
layout: cover
---

# Podman, Dev Containers, and dctl

Podman/libkrun microVM workflows with shared `Containerfile` assets and
manifest-driven config composition.

---
layout: center
class: act-podman
---

# Raw Podman

- You own the `Containerfile`
- You own the `podman build` and `podman run` argv
- You own post-create bootstrap after startup

```bash
podman build -t snackbar-api-dev:latest .
podman run -d --name snackbar-api-dev ...
podman exec -it snackbar-api-dev bash
```

---
layout: center
class: act-devc
---

# Dev Containers

- Declarative runtime config in `devcontainer.json`
- Lifecycle hooks such as `postCreateCommand`
- Still one `Containerfile` plus one config file per repo

Use `build.dockerfile = "Containerfile"` in `devcontainer.json` and keep the
build context beside the repo.

---
layout: center
class: act-dctl
---

# dctl

- Shared `Containerfile`s under `~/.config/dctl/images/`
- Shared manifest layers under `~/.config/dctl/devcontainer/`
- Cached merged configs under `~/.cache/dctl/devcontainer/`
- Podman/libkrun runtime defaults handled for you

```bash
dctl deploy devcontainer python
dctl deploy image python-dev
dctl init --devcontainer python
dctl ws up
```

---
layout: center
class: act-dctl
---

# Why it lands differently

- One image catalog instead of per-repo image drift
- One composition system for shared and leaf config
- One workspace-aware container identity model
- One command surface over Podman/libkrun microVMs

---
layout: center
class: act-dctl
---

# Summary

Raw Podman is the low-level controller.  
Dev Containers add declarative runtime config.  
`dctl` adds shared `Containerfile` assets, manifest composition, and
workspace-aware orchestration on top.
