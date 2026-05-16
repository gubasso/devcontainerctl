# shellcheck shell=bash

[[ -n ${_DCTL_LIB_REGISTRY_VALIDATE_LOADED:-} ]] && return 0
readonly _DCTL_LIB_REGISTRY_VALIDATE_LOADED=1

__dctl_require _lib/log.sh

_validate_registry() {
  local registry="$1"

  # Empty file is a valid empty registry
  if [[ ! -s $registry ]]; then
    return 0
  fi

  # File with only whitespace/comments parses as null — treat as empty
  local root_tag
  root_tag="$(yq eval 'type' "$registry" 2>/dev/null || true)"
  if [[ $root_tag == "!!null" ]]; then
    return 0
  fi

  # Prefer check-jsonschema for full validation
  if command -v check-jsonschema >/dev/null 2>&1; then
    local schema="${DCTL_SCHEMAS_DIR}/projects.schema.yaml"
    if [[ -f $schema ]]; then
      local validation_output
      if ! validation_output="$(check-jsonschema --schemafile "$schema" "$registry" 2>&1)"; then
        err "Schema validation failed for $registry: $validation_output"
      fi
      return 0
    fi
  fi

  # Fallback: yq structural checks
  # Verify the file is valid YAML
  if ! yq eval '.' "$registry" >/dev/null 2>&1; then
    err "Invalid YAML in $registry"
  fi

  # Root must be a mapping (null already handled above)
  if [[ $root_tag != "!!map" ]]; then
    err "Invalid registry format in $registry: root must be a mapping, got $root_tag"
  fi

  # Check that all project values are mappings
  local bad_type
  bad_type="$(yq eval '
    to_entries | .[] | select(.value | type != "!!map") | .key
  ' "$registry" 2>/dev/null || true)"
  if [[ -n $bad_type ]]; then
    err "Invalid entry in $registry: '$bad_type' must be a mapping"
  fi

  # Check for unrecognized keys
  local bad_keys
  bad_keys="$(yq eval '
    to_entries | .[].value | to_entries | .[] |
    select(.key != "devcontainer-manifest" and .key != "sibling_discovery") |
    .key
  ' "$registry" 2>/dev/null || true)"
  if [[ -n $bad_keys ]]; then
    err "Unrecognized key in $registry: $bad_keys"
  fi

  # Check string fields are strings
  local bad_str
  bad_str="$(yq eval '
    to_entries | .[].value |
    select(has("devcontainer-manifest")) |
    select(.["devcontainer-manifest"] | type != "!!str") |
    parent | to_entries | .[0].key
  ' "$registry" 2>/dev/null || true)"
  if [[ -n $bad_str ]]; then
    err "Invalid type for devcontainer-manifest in $registry: expected string"
  fi

  # Check devcontainer-manifest values match the schema pattern
  # (mirrors the JSON schema's ^[A-Za-z0-9._-]+$ when check-jsonschema is unavailable)
  local bad_pattern
  bad_pattern="$(yq eval '
    to_entries | .[] |
    select(.value["devcontainer-manifest"]) |
    select(.value["devcontainer-manifest"] | test("^[A-Za-z0-9._-]+$") | not) |
    .key
  ' "$registry" 2>/dev/null || true)"
  if [[ -n $bad_pattern ]]; then
    err "Invalid devcontainer-manifest value in $registry for project '$bad_pattern': must match ^[A-Za-z0-9._-]+\$"
  fi

  # Check sibling_discovery is boolean if present
  local bad_bool
  bad_bool="$(yq eval '
    to_entries | .[].value |
    select(has("sibling_discovery")) |
    select(.sibling_discovery | type != "!!bool") |
    parent | to_entries | .[0].key
  ' "$registry" 2>/dev/null || true)"
  if [[ -n $bad_bool ]]; then
    err "Invalid type for sibling_discovery in $registry: expected boolean"
  fi
}
