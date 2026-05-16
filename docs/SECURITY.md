# Security Model

## Threat Model

`dctl` assumes AI agents execute attacker-controlled commands. After the move to
libkrun, the most common remaining risks are still token exfiltration and open
network egress rather than container escape. See
`docs/specs/sandbox-runtime/SPEC.md` section 3.1.

## Tier 0 Hygiene

The default path now applies the low-cost controls required by round 40:

- `/tmp` is a tmpfs (`--tmpfs /tmp:rw,nosuid,nodev,size=1g`), not a host bind.
- The agents layer adds `--cap-drop=ALL`.
- The agents layer adds `--security-opt no-new-privileges`.
- The bwrap-oriented seccomp and AppArmor settings remain for Codex CLI
  compatibility, but under libkrun they are no longer the load-bearing
  isolation boundary. The hypervisor boundary is.

Tier 3 cleanup of the inner seccomp/AppArmor posture remains deferred per
`docs/specs/sandbox-runtime/SPEC.md` section 5.4.

## Token Forwarding

Long-lived host auth directories are no longer mounted into the container.

- GitHub auth is forwarded as `GH_TOKEN`, resolved on the host from `GH_TOKEN`,
  `GITHUB_TOKEN`, or `gh auth token`.
- GitLab auth is forwarded as `GITLAB_TOKEN`, resolved on the host from
  `GITLAB_TOKEN` or `glab auth status --show-token`.

Those env vars are injected on `podman exec`, not by bind-mounting
`~/.config/gh` or `~/.config/glab-cli`.

## Ephemeral Session Credentials

Claude, Codex, and Gemini credentials are copied into a per-workspace session
cache and mounted read-only from there. The session root is:

`$DCTL_CACHE_DIR/sessions/<sha1(realpath(workspace))>/`

The current projection map is:

- Claude: first match of `~/.claude/.credentials.json`,
  `~/.claude/credentials.json`, or `~/.claude.json`
- Codex: `~/.codex/auth.json`
- Gemini: `~/.gemini/key.json` and `~/.gemini/oauth_creds.json` when present

Only those minimal credential files are copied. Agent history, project state,
and other cached artifacts are not projected into the container. The session
cache is deleted by `dctl ws down`, including the no-container cleanup path.

## Egress Allowlist

Default container egress is deny-by-default and enforced inside the guest with
`nftables`, not on the host. The bootstrap script is
`/usr/local/bin/dctl-egress`, launched by the base layer's `postStartCommand`.

The default allowlist includes:

- `api.anthropic.com`
- `api.openai.com`
- `*.googleapis.com`
- `registry.npmjs.org`
- `pypi.org`
- `files.pythonhosted.org`
- `crates.io`
- `index.crates.io`
- `download.opensuse.org`
- `github.com`
- `*.githubusercontent.com`
- `gitlab.com`
- `*.gitlab.io`
- the workspace's git remote hosts

Users extend the set with `dctl net allow <host>`. The in-guest allowlist is
refreshed every 300 seconds. If nftables cannot be installed, container startup
fails closed and `dctl` removes the container.

Wildcard DNS entries are intentionally limited. The current implementation does
not expand wildcard hostnames into concrete DNS names; add the concrete host
with `dctl net allow` if a workflow depends on one.

## Open Claude Question

Anthropic does not currently publish a documented short-lived token export path
equivalent to `gh auth token`. The ephemeral file copy described above is the
current mitigation until a better host-side export path exists. This remains an
open question in `docs/specs/sandbox-runtime/SPEC.md` section 8.

## Permissive Profile

This repository now ships `devcontainers/agents-permissive/` defensively
because the KVM-bearing bwrap smoke cannot run in this environment. The default
`agents` layer keeps `cap-drop=ALL` and `no-new-privileges`; the permissive
profile exists as the explicit fallback for workflows that prove they still need
the looser outer posture for nested `bwrap`.
