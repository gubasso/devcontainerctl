# shellcheck shell=bash

[[ -n ${_DCTL_LIB_REGISTRY_VALIDATE_MANIFEST_LOADED:-} ]] && return 0
readonly _DCTL_LIB_REGISTRY_VALIDATE_MANIFEST_LOADED=1

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh

_validate_compose_manifest() {
  local manifest="$1"

  [[ -f $manifest ]] || err "Manifest not found: $manifest"
  [[ -s $manifest ]] || err "Manifest is empty: $manifest"

  if command -v check-jsonschema >/dev/null 2>&1; then
    local schema="${DCTL_SCHEMAS_DIR}/compose.schema.yaml"
    if [[ -f $schema ]]; then
      local validation_output
      if ! validation_output="$(check-jsonschema --schemafile "$schema" "$manifest" 2>&1)"; then
        err "Schema validation failed for $manifest: $validation_output"
      fi
      return 0
    fi
  fi

  if ! yq eval '.' "$manifest" >/dev/null 2>&1; then
    err "Invalid YAML in manifest: $manifest"
  fi

  local layers_type
  layers_type="$(yq eval '.layers | type' "$manifest" 2>/dev/null || true)"
  if [[ $layers_type != "!!seq" ]]; then
    err "Invalid manifest $manifest: 'layers' must be an array"
  fi

  local layers_len
  layers_len="$(yq eval '.layers | length' "$manifest" 2>/dev/null || true)"
  if [[ $layers_len -eq 0 ]]; then
    err "Invalid manifest $manifest: 'layers' must not be empty"
  fi
}
