# shellcheck shell=bash

[[ -n ${_DCTL_LIB_JSON_STRIP_COMMENTS_LOADED:-} ]] && return 0
readonly _DCTL_LIB_JSON_STRIP_COMMENTS_LOADED=1

_strip_jsonc_comments() {
  sed '/^[[:space:]]*\/\//d' "$1"
}
