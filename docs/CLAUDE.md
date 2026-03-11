# CLAUDE.md — devcontainerctl

Pre-built Docker images and the unified `dctl` CLI for AI-agent devcontainer sandboxes.

## Quick Orientation

- `bin/dctl` — single CLI entrypoint (image builds + workspace lifecycle)
- `images/` — Dockerfiles, one subdir per image
- `systemd/` — weekly image rebuild timer + service
- `templates/` — devcontainer.json project templates

## References

- [README.md](../README.md) — install, CLI usage, automation
- [QUICKSTART.md](QUICKSTART.md) — project setup templates and common commands
- [ARCHITECTURE.md](ARCHITECTURE.md) — container/image design rationale and mount patterns
