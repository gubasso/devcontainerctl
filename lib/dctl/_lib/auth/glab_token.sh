# shellcheck shell=bash

[[ -n ${_DCTL_LIB_AUTH_GLAB_TOKEN_LOADED:-} ]] && return 0
readonly _DCTL_LIB_AUTH_GLAB_TOKEN_LOADED=1

__dctl_require _lib/log.sh

_extract_glab_token() {
  if [[ -n ${GITLAB_TOKEN:-} ]]; then
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
  if [[ -z $token ]]; then
    warn "Failed to extract glab token"
    return 1
  fi
  printf '%s' "$token"
}
