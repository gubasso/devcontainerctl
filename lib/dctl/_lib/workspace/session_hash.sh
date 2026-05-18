# shellcheck shell=bash

[[ -n ${_DCTL_LIB_WORKSPACE_SESSION_HASH_LOADED:-} ]] && return 0
readonly _DCTL_LIB_WORKSPACE_SESSION_HASH_LOADED=1

__dctl_require _lib/paths.sh

workspace_session_hash() {
  local folder="${1:-$WORKSPACE_FOLDER}"
  local canonical
  canonical="$(cd -- "$folder" && pwd -P)" || return 1
  printf '%s' "$canonical" | sha1sum | awk '{print $1}'
}

workspace_session_dir() {
  local hash
  hash="$(workspace_session_hash "$@")" || return 1
  printf '%s/sessions/%s\n' "$DCTL_CACHE_DIR" "$hash"
}
