# CLAUDE.md — devcontainerctl

Pre-built Docker images and the unified `dctl` CLI for AI-agent devcontainer sandboxes.

## Quick Orientation

- `bin/dctl` — thin CLI entrypoint (bootstrap, source modules, dispatch)
- `lib/dctl/` — shell library modules (common, ws, image)
- `images/` — Dockerfiles, one subdir per image
- `systemd/` — weekly image rebuild timer + service
- `templates/` — devcontainer.json project templates

## References

- [README.md](../README.md) — install, CLI usage, automation
- [QUICKSTART.md](QUICKSTART.md) — project setup templates and common commands
- [ARCHITECTURE.md](ARCHITECTURE.md) — container/image design rationale and mount patterns
