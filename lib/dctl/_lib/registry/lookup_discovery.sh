# shellcheck shell=bash

[[ -n ${_DCTL_LIB_REGISTRY_LOOKUP_DISCOVERY_LOADED:-} ]] && return 0
readonly _DCTL_LIB_REGISTRY_LOOKUP_DISCOVERY_LOADED=1

__dctl_require _lib/registry/file.sh
__dctl_require _lib/registry/exists.sh
__dctl_require _lib/registry/validate.sh
__dctl_require _lib/log.sh

_registry_lookup_sibling_discovery() {
  local canonical_name="$1"
  local registry
  registry="$(_registry_file)"

  if ! _registry_exists; then
    printf 'true\n'
    return 0
  fi

  if ! command -v yq >/dev/null 2>&1; then
    err "Missing required command: yq — install from https://github.com/mikefarah/yq"
  fi
  _validate_registry "$registry"

  # Cannot use // (alternative) operator because false is falsy in yq.
  # Check if the key exists, then read its value directly.
  local has_key
  has_key="$(yq -r ".\"${canonical_name}\" | has(\"sibling_discovery\")" "$registry" 2>/dev/null || true)"
  if [[ $has_key == "true" ]]; then
    yq -r ".\"${canonical_name}\".sibling_discovery" "$registry"
  else
    printf 'true\n'
  fi
}
