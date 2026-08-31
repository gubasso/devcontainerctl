# shellcheck shell=bash
# Forge auth for dctl (sourced, not executed directly)
#
# The seeding itself lives in the host tool `forge-seed` (nix-secrets,
# home/apps/forge-seed): it materializes keyring-held gh/glab credentials into
# an ephemeral per-scope directory on tmpfs. dctl is one consumer of that
# contract — the convention is specified in docs/specs/secret-forwarding/
# SPEC.md. At up and on every exec dctl re-seeds, bind-mounts the seed dir at
# /run/forge-auth, and points GH_CONFIG_DIR/GLAB_CONFIG_DIR at it. The
# container receives paths, never secrets: no token ever enters a --remote-env
# argument or the container environment.
#
# The seed dir is a live bind: re-seeding at exec time updates what an
# already-running container sees, so a rotated token propagates with no reup.

[[ -n ${_DCTL_AUTH_LOADED:-} ]] && return 0
readonly _DCTL_AUTH_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/common.sh"

# Still needed by image.sh, which passes the token as a BuildKit --secret at
# image build time (never into a running container).
_extract_gh_token() {
  if [[ -n ${GH_TOKEN:-} ]]; then
    printf '%s' "$GH_TOKEN"
    return 0
  fi
  if [[ -n ${GITHUB_TOKEN:-} ]]; then
    printf '%s' "$GITHUB_TOKEN"
    return 0
  fi
  if ! command -v gh >/dev/null 2>&1; then
    warn "gh CLI not found — install from https://cli.github.com"
    return 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    warn "gh not authenticated — run 'gh auth login' on the host"
    return 1
  fi
  local token
  token=$(gh auth token 2>/dev/null)
  if [[ -z $token ]]; then
    warn "Failed to extract gh token"
    return 1
  fi
  printf '%s' "$token"
}

# Seed (idempotent, warn-don't-fail) and print the per-project seed dir.
# Fails only when forge-seed itself is absent: it is an optional runtime
# dependency, like yq — auth must never hard-fail an up or exec, so the
# container simply runs unauthenticated for the forges.
forge_auth_seed_dir() {
  if ! command -v forge-seed >/dev/null 2>&1; then
    warn "forge-seed not found — container runs without forge auth (nix-secrets home/apps/forge-seed)"
    return 1
  fi
  forge-seed --scope "$(resolve_canonical_project_name)" --print-dir
}

# Usage: local -a mounts=(); collect_forge_auth_mounts mounts
collect_forge_auth_mounts() {
  # shellcheck disable=SC2178
  local -n _out="$1"
  # shellcheck disable=SC2034
  _out=()
  # Require a real directory before mounting: forge-seed can exit 0 with no
  # output (its own warn-don't-fail contract, e.g. when the seed root cannot
  # be created), and an empty or dangling source would fail devcontainer up
  # instead of degrading.
  local dir
  if dir="$(forge_auth_seed_dir)" && [[ -n $dir && -d $dir ]]; then
    _out+=(--mount "type=bind,source=${dir},target=/run/forge-auth")
  else
    warn "forge auth seed unavailable — container starts without /run/forge-auth"
  fi
  # Forward the agent socket, never key material. The -S guard matches
  # collect_forge_auth_env: variable and socket are both present or both
  # absent, or ssh fails on a dead socket instead of falling back to keys.
  # The socket is a dctl feature, not part of the forge-seed contract, so it
  # keeps the dctl-branded target path.
  if [[ -n ${SSH_AUTH_SOCK:-} && -S ${SSH_AUTH_SOCK} ]]; then
    _out+=(--mount "type=bind,source=${SSH_AUTH_SOCK},target=/run/dctl/ssh-agent.sock")
  fi
}

# Usage: local -a env_args=(); collect_forge_auth_env env_args
# No token ever enters this array — only fixed container paths. The config-dir
# vars are emitted even when seeding failed: they match the base payload's
# static containerEnv, and pointing at an absent dir is the accepted
# degradation (gh/glab run unauthenticated, ssh falls back to key files).
collect_forge_auth_env() {
  # shellcheck disable=SC2178
  local -n _out="$1"
  # shellcheck disable=SC2034
  _out=()
  forge_auth_seed_dir >/dev/null || true
  _out+=(--remote-env "GH_CONFIG_DIR=/run/forge-auth/gh")
  _out+=(--remote-env "GLAB_CONFIG_DIR=/run/forge-auth/glab-cli")
  if [[ -n ${SSH_AUTH_SOCK:-} && -S ${SSH_AUTH_SOCK} ]]; then
    _out+=(--remote-env "SSH_AUTH_SOCK=/run/dctl/ssh-agent.sock")
  fi
}
