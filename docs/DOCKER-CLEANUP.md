# Docker & Devcontainer Cleanup Guide

Operator guide for reclaiming disk and removing legacy Docker/BuildKit/devcontainer state. Ordered from **inspect → safe cleanup → targeted dctl cleanup → aggressive reset**. Use the earliest step that solves your problem.

> Quick mental model. Docker keeps five things that grow: **containers** (stopped or running), **images** (tagged, untagged/dangling), **volumes** (named + anonymous), **networks** (ephemeral per `docker compose` / devcontainer run), and the **BuildKit cache** (layer blobs + intermediate stages). Each needs its own command to reclaim — `docker system prune` skips some of them by default.

## 1. Inspect what you have

Before deleting anything, measure.

```bash
# Overall usage: containers, images, volumes, build cache (sizes and reclaimable)
docker system df

# Detailed per-object breakdown
docker system df -v | less

# Images grouped by repository, largest first
docker images --format '{{.Size}}\t{{.Repository}}:{{.Tag}}\t{{.ID}}' | sort -h

# Stopped containers (candidates for removal)
docker ps -a --filter status=exited --filter status=dead --filter status=created \
  --format 'table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}'

# Dangling images (untagged, produced by rebuilds)
docker images --filter dangling=true

# Unused volumes (no container references them)
docker volume ls --filter dangling=true

# BuildKit cache usage
docker buildx du | head
```

## 2. Safe cleanup (non-destructive to running work)

Each step is independent — run any subset. None of these touch running containers or tagged images you still use.

```bash
# Remove stopped containers
docker container prune -f

# Remove dangling (untagged) images
docker image prune -f

# Remove unused networks
docker network prune -f

# Remove BuildKit layers unused for >72h (keep recent rebuild speed)
docker buildx prune --filter 'until=72h' -f

# Remove volumes not referenced by any container
#   WARNING: devcontainers often keep volumes (e.g. dotfiles cache, bun cache,
#   cargo target). If you rely on those, skip this or use the targeted form below.
docker volume prune -f
```

Verify reclamation:

```bash
docker system df
```

## 3. Targeted dctl-aware cleanup

`dctl` tags its images `devimg/<name>:latest` and labels its devcontainers with `devcontainer.local_folder=<workspace-path>`. Use these to clean up without touching other Docker work on the host.

### 3.1 Devcontainer for the current workspace

```bash
# From inside the workspace directory:
dctl ws status    # see what's there
dctl ws down      # remove the container for this workspace
```

`dctl ws down` removes only the containers labeled with the current workspace path. It does not touch images, volumes, or other workspaces.

### 3.2 All dctl-managed workspace containers (any workspace)

```bash
docker ps -a --filter 'label=devcontainer.local_folder' \
  --format 'table {{.ID}}\t{{.Status}}\t{{.Label "devcontainer.local_folder"}}\t{{.Image}}'

# Remove them all (running or stopped):
docker ps -aq --filter 'label=devcontainer.local_folder' | xargs -r docker rm -f
```

### 3.3 dctl-managed images

```bash
# List managed images
docker images 'devimg/*'

# Remove a single managed image (forces rebuild next time)
docker image rm devimg/python-dev:latest

# Remove ALL managed images (safe — rebuild via `dctl image build --full-rebuild`)
docker images --format '{{.Repository}}:{{.Tag}}' 'devimg/*' | xargs -r docker image rm
```

### 3.4 Post-migration: wipe the old Debian-based image chain

After migrating the base image (Debian → openSUSE Leap 16.0, or any similar base change), the old layers stay cached and can eat tens of GB.

```bash
# 1. Make sure no workspace is running against the old images:
docker ps -a --filter 'label=devcontainer.local_folder'
#    → if any container shows an old image, `dctl ws down` in its workspace or
#    `docker rm -f <id>` on it.

# 2. Remove all dctl-managed tags (old and new — you'll rebuild them):
docker images --format '{{.Repository}}:{{.Tag}}' 'devimg/*' | xargs -r docker image rm

# 3. Remove the now-dangling Debian base layers pulled as parents:
docker image prune -f

# 4. (Optional) also drop the Debian base itself, if nothing else uses it:
docker image rm debian:trixie-slim debian:bookworm 2>/dev/null || true

# 5. Drop BuildKit cache layers for the old chain:
docker buildx prune -f
#    Add `--all` if you want to nuke every cached layer (slower next build).

# 6. Rebuild from the new base with no cache:
dctl image build --full-rebuild
```

Steps 2 + 5 are the main space-reclaimers after a base swap.

## 4. Aggressive reset (destroys everything Docker)

Use only when you genuinely want a clean Docker state. **This stops and removes every container, image, volume, and cache on the host** — not just dctl's. Never run this on a host that hosts production workloads.

```bash
# Stop and remove every container (running or not)
docker ps -aq | xargs -r docker rm -f

# Remove every image
docker images -q | xargs -r docker image rm -f

# Remove every volume
docker volume ls -q | xargs -r docker volume rm -f

# Remove every network (except the built-ins `bridge`, `host`, `none`)
docker network ls -q --filter 'type=custom' | xargs -r docker network rm

# Nuke the entire BuildKit cache
docker buildx prune --all -f

# One-shot equivalent for everything the API will prune:
docker system prune --all --volumes -f
```

`docker system prune --all --volumes -f` is the closest single command, but it still leaves: (a) running containers, (b) named volumes not created by `docker volume create` but attached to a removed container (usually safe), (c) BuildKit cache older than the current builder — run `docker buildx prune --all -f` separately to guarantee it.

### 4.1 Full Docker daemon reset (host-level, last resort)

If Docker itself is in a bad state (stuck daemon, corrupt storage driver, etc.):

```bash
sudo systemctl stop docker docker.socket
sudo rm -rf /var/lib/docker             # destroys every image, container, volume
sudo systemctl start docker
```

This is destructive *and* requires root. Prefer step 4 first.

## 5. Devcontainer-specific leftovers

The `devcontainer` CLI (used by `dctl ws up`) caches feature installers and intermediate images. These usually get pruned by the above steps, but can linger.

```bash
# Devcontainer CLI cache (feature layers, dev-container builds)
rm -rf ~/.devcontainer/                 # CLI state
rm -rf ~/.cache/devcontainers-cli/      # some versions
rm -rf ~/.cache/dctl/                   # dctl resolved state (safe — recomputed)

# Per-project ephemeral state (dctl writes nothing here by default, but check):
find . -name '.devcontainer.build-*' -type d
```

The `dctl` CLI keeps its own state under `~/.config/dctl/` (configuration — do **not** delete unless reinstalling) and `~/.cache/dctl/` (regenerable — safe to delete).

## 6. Routine housekeeping

Add this to a weekly cron / systemd timer to keep things in check without manual work:

```bash
# /etc/cron.weekly/docker-cleanup  (chmod +x)
#!/usr/bin/env bash
set -euo pipefail

docker container prune -f
docker image prune -f
docker network prune -f
docker buildx prune --filter 'until=168h' -f   # keep one week of build cache
# Skip `volume prune` in automation — too easy to lose devcontainer state.
```

For a systemd timer instead of cron, model it after the existing `systemd/dctl-image-build.timer` in this repo.

## 7. Verify reclamation worked

```bash
# Before:
docker system df

# Clean up:
# ... run the steps you picked from above ...

# After:
docker system df
```

The "RECLAIMABLE" column in `docker system df` should drop toward 0% for each row you targeted. If it doesn't, something still references those objects — rerun `docker ps -a` and `docker images --all` to find out what.

## 8. One-shot full wipe

Single copy-pasteable block to remove **everything** dctl, Docker, and devcontainer-related on the host. Combines sections 2, 3, 4, 4.1, and 5 into one sequence. **Destroys every container, image, volume, network, BuildKit cache, and CLI state on the host** — not just dctl's. Never run on a host with production workloads.

```bash
# 1. Stop and remove every container (running or not)
docker ps -aq | xargs -r docker rm -f

# 2. Remove every image
docker images -q | xargs -r docker image rm -f

# 3. Remove every volume
docker volume ls -q | xargs -r docker volume rm -f

# 4. Remove every custom network
docker network ls -q --filter 'type=custom' | xargs -r docker network rm

# 5. Nuke the entire BuildKit cache
docker buildx prune --all -f

# 6. One-shot API-level prune as a safety net
docker system prune --all --volumes -f

# 7. Remove devcontainer CLI and dctl cache/state
rm -rf ~/.devcontainer/
rm -rf ~/.cache/devcontainers-cli/
rm -rf ~/.cache/dctl/

# 8. (Last resort) full Docker daemon reset — requires root, destroys /var/lib/docker
sudo systemctl stop docker docker.socket
sudo rm -rf /var/lib/docker
sudo systemctl start docker
```

Verify with `docker system df` — every row should report 0B / 0% reclaimable. To rebuild dctl-managed images from scratch afterwards:

```bash
dctl image build --full-rebuild
```

Step 8 is optional and only needed if the daemon itself is in a bad state. `~/.config/dctl/` is preserved — delete it manually only if reinstalling dctl from zero.

## References

- Docker prune docs: <https://docs.docker.com/engine/manage-resources/pruning/>
- BuildKit cache management: <https://docs.docker.com/build/cache/>
- `dctl` CLI surface: `dctl help`, `dctl image help`, `dctl ws help`
- Related repo docs: [ARCHITECTURE.md](ARCHITECTURE.md), [QUICKSTART.md](QUICKSTART.md)
