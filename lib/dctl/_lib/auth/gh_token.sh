# shellcheck shell=bash

[[ -n ${_DCTL_LIB_AUTH_GH_TOKEN_LOADED:-} ]] && return 0
readonly _DCTL_LIB_AUTH_GH_TOKEN_LOADED=1

__dctl_require _lib/log.sh

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
