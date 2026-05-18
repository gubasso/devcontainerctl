# shellcheck shell=bash

[[ -n ${_DCTL_LIB_REGISTRY_READ_MANIFEST_LAYERS_LOADED:-} ]] && return 0
readonly _DCTL_LIB_REGISTRY_READ_MANIFEST_LAYERS_LOADED=1

_read_manifest_layers() {
  local manifest="$1"
  yq eval '.layers[]' "$manifest"
}
