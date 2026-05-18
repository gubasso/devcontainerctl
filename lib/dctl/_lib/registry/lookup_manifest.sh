# shellcheck shell=bash

[[ -n ${_DCTL_LIB_REGISTRY_LOOKUP_MANIFEST_LOADED:-} ]] && return 0
readonly _DCTL_LIB_REGISTRY_LOOKUP_MANIFEST_LOADED=1

__dctl_require _lib/registry/read_field.sh

_registry_lookup_devcontainer_manifest() {
  local canonical_name="$1"
  _registry_read_field "$canonical_name" "devcontainer-manifest"
}
