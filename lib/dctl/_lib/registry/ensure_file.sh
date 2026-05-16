# shellcheck shell=bash

[[ -n ${_DCTL_LIB_REGISTRY_ENSURE_FILE_LOADED:-} ]] && return 0
readonly _DCTL_LIB_REGISTRY_ENSURE_FILE_LOADED=1

__dctl_require _lib/registry/file.sh

_registry_ensure_file() {
  local registry
  registry="$(_registry_file)"
  mkdir -p "$(dirname "$registry")"
  if [[ ! -f $registry ]]; then
    touch "$registry"
  fi
}
