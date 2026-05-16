# shellcheck shell=bash

[[ -n ${_DCTL_LIB_AUTH_COLLECT_ENV_LOADED:-} ]] && return 0
readonly _DCTL_LIB_AUTH_COLLECT_ENV_LOADED=1

__dctl_require _lib/auth/gh_token.sh
__dctl_require _lib/auth/glab_token.sh

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
