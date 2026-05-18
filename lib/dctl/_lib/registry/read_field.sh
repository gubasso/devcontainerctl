# shellcheck shell=bash

[[ -n ${_DCTL_LIB_REGISTRY_READ_FIELD_LOADED:-} ]] && return 0
readonly _DCTL_LIB_REGISTRY_READ_FIELD_LOADED=1

__dctl_require _lib/registry/file.sh
__dctl_require _lib/registry/exists.sh
__dctl_require _lib/registry/validate.sh
__dctl_require _lib/log.sh

_registry_read_field() {
  local canonical_name="$1"
  local field="$2"
  local registry
  registry="$(_registry_file)"

  _registry_exists || return 0

  if ! command -v yq >/dev/null 2>&1; then
    err "Missing required command: yq — install from https://github.com/mikefarah/yq"
  fi

  _validate_registry "$registry"

  local value
  value="$(yq -r "(.\"${canonical_name}\"[\"${field}\"]) // \"\"" "$registry" 2>/dev/null || true)"
  [[ -n $value ]] && printf '%s\n' "$value"
  return 0
}
