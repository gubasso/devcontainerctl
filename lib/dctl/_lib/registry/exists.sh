# shellcheck shell=bash

[[ -n ${_DCTL_LIB_REGISTRY_EXISTS_LOADED:-} ]] && return 0
readonly _DCTL_LIB_REGISTRY_EXISTS_LOADED=1

__dctl_require _lib/registry/file.sh

_registry_exists() {
  local registry
  registry="$(_registry_file)"
  [[ -f $registry ]]
}
