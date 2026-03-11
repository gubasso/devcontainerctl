# shellcheck shell=bash
# Shared primitives for dctl modules (sourced, not executed directly)

[[ -n "${_DCTL_COMMON_LOADED:-}" ]] && return 0
readonly _DCTL_COMMON_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"
: "${DCTL_VERSION:=dev}"
: "${WORKSPACE_FOLDER:=.}"
: "${IMAGES_DIR:=${XDG_DATA_HOME:-$HOME/.local/share}/dctl/images}"

readonly DCTL_VERSION
readonly WORKSPACE_FOLDER
readonly IMAGES_DIR

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

workspace_path() {
  pwd -P
}

workspace_label_filter() {
  printf 'label=devcontainer.local_folder=%s' "$(workspace_path)"
}
