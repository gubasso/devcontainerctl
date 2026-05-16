# shellcheck shell=bash

[[ -n ${_DCTL_LIB_LOG_LOADED:-} ]] && return 0
readonly _DCTL_LIB_LOG_LOADED=1

log() {
  printf '\033[1;34m==>\033[0m %s\n' "$1"
}

warn() {
  printf '\033[1;33mWARN:\033[0m %s\n' "$1" >&2
}

err() {
  printf '\033[1;31mERROR:\033[0m %s\n' "$1" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || err "Missing required command: $cmd"
}
