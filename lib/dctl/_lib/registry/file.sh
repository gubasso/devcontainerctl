# shellcheck shell=bash

[[ -n ${_DCTL_LIB_REGISTRY_FILE_LOADED:-} ]] && return 0
readonly _DCTL_LIB_REGISTRY_FILE_LOADED=1

_registry_file() {
  printf '%s/projects.yaml\n' "$DCTL_CONFIG_DIR"
}
