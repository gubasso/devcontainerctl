# shellcheck shell=bash
# Project registry module for dctl (sourced, not executed directly)

[[ -n "${_DCTL_CONFIG_LOADED:-}" ]] && return 0
readonly _DCTL_CONFIG_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/common.sh"

: "${DCTL_SCHEMAS_DIR:=${XDG_DATA_HOME:-$HOME/.local/share}/dctl/schemas}"
readonly DCTL_SCHEMAS_DIR

_registry_file() {
  printf '%s/projects.yaml\n' "$DCTL_CONFIG_DIR"
}

_registry_exists() {
  local registry
  registry="$(_registry_file)"
  [[ -f "$registry" ]]
}

_validate_registry() {
  local registry="$1"

  # Empty file is a valid empty registry
  if [[ ! -s "$registry" ]]; then
    return 0
  fi

  # Prefer check-jsonschema for full validation
  if command -v check-jsonschema >/dev/null 2>&1; then
    local schema="${DCTL_SCHEMAS_DIR}/projects.schema.yaml"
    if [[ -f "$schema" ]]; then
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

  # Root must be a mapping
  local root_type
  root_type="$(yq eval 'type' "$registry" 2>/dev/null || true)"
  if [[ "$root_type" != "!!map" ]]; then
    err "Invalid registry format in $registry: root must be a mapping, got $root_type"
  fi

  # Check that all project values are mappings
  local bad_type
  bad_type="$(yq eval '
    to_entries | .[] | select(.value | type != "!!map") | .key
  ' "$registry" 2>/dev/null || true)"
  if [[ -n "$bad_type" ]]; then
    err "Invalid entry in $registry: '$bad_type' must be a mapping"
  fi

  # Check for unrecognized keys
  local bad_keys
  bad_keys="$(yq eval '
    to_entries | .[].value | to_entries | .[] |
    select(.key != "devcontainer" and .key != "dockerfile" and .key != "image" and .key != "sibling_discovery") |
    .key
  ' "$registry" 2>/dev/null || true)"
  if [[ -n "$bad_keys" ]]; then
    err "Unrecognized key in $registry: $bad_keys"
  fi

  # Check string fields are strings
  local field
  for field in devcontainer dockerfile image; do
    local bad_str
    bad_str="$(yq eval '
      to_entries | .[].value |
      select(has("'"$field"'")) |
      select(.'"$field"' | type != "!!str") |
      parent | to_entries | .[0].key
    ' "$registry" 2>/dev/null || true)"
    if [[ -n "$bad_str" ]]; then
      err "Invalid type for $field in $registry: expected string"
    fi
  done

  # Check sibling_discovery is boolean if present
  local bad_bool
  bad_bool="$(yq eval '
    to_entries | .[].value |
    select(has("sibling_discovery")) |
    select(.sibling_discovery | type != "!!bool") |
    parent | to_entries | .[0].key
  ' "$registry" 2>/dev/null || true)"
  if [[ -n "$bad_bool" ]]; then
    err "Invalid type for sibling_discovery in $registry: expected boolean"
  fi
}

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
  value="$(yq -r ".\"${canonical_name}\".${field} // \"\"" "$registry" 2>/dev/null || true)"
  [[ -n "$value" ]] && printf '%s\n' "$value"
  return 0
}

# Override the stubs from common.sh
_registry_lookup_devcontainer() {
  local canonical_name="$1"
  _registry_read_field "$canonical_name" "devcontainer"
}

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
  if [[ "$has_key" == "true" ]]; then
    yq -r ".\"${canonical_name}\".sibling_discovery" "$registry"
  else
    printf 'true\n'
  fi
}

_registry_lookup_dockerfile() {
  local canonical_name="$1"
  _registry_read_field "$canonical_name" "dockerfile"
}

usage_config() {
  cat <<'EOF'
Usage: dctl config <command>

Commands:
  help    Show this help text

Project registry: ~/.config/dctl/projects.yaml
EOF
}

cmd_config() {
  local command="${1:-help}"
  case "$command" in
    help | -h | --help)
      usage_config
      ;;
    *)
      err "Unknown config command: $command"
      ;;
  esac
}

main_config() {
  cmd_config "$@"
}
