# shellcheck shell=bash

[[ -n ${_DCTL_LIB_REGISTRY_HAS_PROJECT_LOADED:-} ]] && return 0
readonly _DCTL_LIB_REGISTRY_HAS_PROJECT_LOADED=1

__dctl_require _lib/registry/file.sh

_registry_has_project() {
  local canonical_name="$1"
  local registry
  registry="$(_registry_file)"
  [[ -s $registry ]] || return 1
  YQ_KEY="$canonical_name" yq -e '.[env(YQ_KEY)]' "$registry" >/dev/null 2>&1
}
