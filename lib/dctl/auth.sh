# shellcheck shell=bash
# Auth token extraction for dctl (sourced, not executed directly)

[[ -n "${_DCTL_AUTH_LOADED:-}" ]] && return 0
readonly _DCTL_AUTH_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/common.sh"

_extract_gh_token() {
  if [[ -n "${GH_TOKEN:-}" ]]; then
    printf '%s' "$GH_TOKEN"
    return 0
  fi
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
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
  if [[ -z "$token" ]]; then
    warn "Failed to extract gh token"
    return 1
  fi
  printf '%s' "$token"
}

_extract_glab_token() {
  if [[ -n "${GITLAB_TOKEN:-}" ]]; then
    printf '%s' "$GITLAB_TOKEN"
    return 0
  fi
  if ! command -v glab >/dev/null 2>&1; then
    warn "glab CLI not found — install from https://gitlab.com/gitlab-org/cli"
    return 1
  fi
  if ! glab auth status >/dev/null 2>&1; then
    warn "glab not authenticated — run 'glab auth login' on the host"
    return 1
  fi
  local token
  token=$(glab auth status --show-token 2>&1 | awk '/Token:/{print $NF}')
  if [[ -z "$token" ]]; then
    warn "Failed to extract glab token"
    return 1
  fi
  printf '%s' "$token"
}

collect_auth_env() {
  local -n _out="$1"
  _out=()
  local token
  if token=$(_extract_gh_token 2>/dev/null); then
    _out+=(--remote-env "GH_TOKEN=${token}")
  fi
  if token=$(_extract_glab_token 2>/dev/null); then
    _out+=(--remote-env "GITLAB_TOKEN=${token}")
  fi
}
