# shellcheck shell=bash
# Project registry module for dctl (sourced, not executed directly)

[[ -n ${_DCTL_CONFIG_LOADED:-} ]] && return 0
readonly _DCTL_CONFIG_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/common.sh"

_registry_file() {
  printf '%s/projects.yaml\n' "$DCTL_CONFIG_DIR"
}

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

_read_manifest_layers() {
  local manifest="$1"
  yq eval '.layers[]' "$manifest"
}

_registry_exists() {
  local registry
  registry="$(_registry_file)"
  [[ -f $registry ]]
}

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

# Override the stubs from common.sh
_registry_lookup_devcontainer_manifest() {
  local canonical_name="$1"
  _registry_read_field "$canonical_name" "devcontainer-manifest"
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
  if [[ $has_key == "true" ]]; then
    yq -r ".\"${canonical_name}\".sibling_discovery" "$registry"
  else
    printf 'true\n'
  fi
}

_registry_ensure_file() {
  local registry
  registry="$(_registry_file)"
  mkdir -p "$(dirname "$registry")"
  if [[ ! -f $registry ]]; then
    touch "$registry"
  fi
}

_registry_has_project() {
  local canonical_name="$1"
  local registry
  registry="$(_registry_file)"
  [[ -s $registry ]] || return 1
  YQ_KEY="$canonical_name" yq -e '.[env(YQ_KEY)]' "$registry" >/dev/null 2>&1
}

register_project_defaults() {
  local canonical_name="$1"
  local manifest_name="$2"
  local force="${3:-false}"

  require_cmd yq
  _registry_ensure_file

  local registry
  registry="$(_registry_file)"

  if [[ -s $registry ]]; then
    if [[ $force == true ]]; then
      if ! yq eval '.' "$registry" >/dev/null 2>&1; then
        err "Invalid YAML in $registry"
      fi
    else
      _validate_registry "$registry"
    fi
  fi

  local project_exists=false
  if _registry_has_project "$canonical_name"; then
    project_exists=true
    if [[ $force != true ]]; then
      warn "Project '$canonical_name' already registered in $registry; skipping"
      return 0
    fi
  fi

  # Use env vars to pass values safely to yq (avoids injection via special chars)
  local existing_sibling="true"
  if [[ $force == true && $project_exists == true ]]; then
    local has_sibling_key
    has_sibling_key="$(YQ_KEY="$canonical_name" yq -r '.[env(YQ_KEY)] | has("sibling_discovery")' "$registry" 2>/dev/null || true)"
    if [[ $has_sibling_key == "true" ]]; then
      existing_sibling="$(YQ_KEY="$canonical_name" yq -r '.[env(YQ_KEY)].sibling_discovery' "$registry" 2>/dev/null || printf 'true\n')"
    fi
  fi

  local yq_expr
  yq_expr='.[env(YQ_KEY)]["devcontainer-manifest"] = strenv(YQ_MANIFEST)'
  if [[ $existing_sibling == "false" ]]; then
    yq_expr+=' | .[env(YQ_KEY)].sibling_discovery = false'
  else
    yq_expr+=' | del(.[env(YQ_KEY)].sibling_discovery)'
  fi
  if [[ $force == true ]]; then
    # Migrate legacy keys registry-wide so a forced write is also a one-shot
    # migration path. For each entry that still has a legacy `devcontainer:`
    # path of the form `<...>/<manifest>/devcontainer.json` (the only shape
    # the prior contract emitted), derive `devcontainer-manifest` from
    # basename(dirname(path)) when the manifest field is not already set.
    # Then drop the legacy `devcontainer`, `dockerfile`, and `image` keys.
    # Entries that have neither key are left untouched. Any derived manifest
    # name that does not match the schema pattern is caught by the post-write
    # _validate_registry call below.
    yq_expr+=' | with_entries(.value |= ('
    yq_expr+='(.["devcontainer-manifest"] = ('
    yq_expr+='(.["devcontainer-manifest"] // (.["devcontainer"] | sub("/devcontainer\.json$"; "") | sub("^.*/"; "")))'
    yq_expr+=')) | ('
    yq_expr+='select(.["devcontainer-manifest"] == null or .["devcontainer-manifest"] == "") '
    yq_expr+='| del(.["devcontainer-manifest"])'
    yq_expr+=') // . '
    yq_expr+='| del(.["devcontainer"]) | del(.dockerfile) | del(.image)'
    yq_expr+='))'
  fi

  local tmp_registry="${registry}.tmp.$$"
  export YQ_KEY="$canonical_name" YQ_MANIFEST="$manifest_name"
  if [[ -s $registry ]]; then
    yq eval "$yq_expr" "$registry" >"$tmp_registry"
  else
    yq -n "$yq_expr" >"$tmp_registry"
  fi
  unset YQ_KEY YQ_MANIFEST

  mv "$tmp_registry" "$registry"
  _validate_registry "$registry"

  log "Registered project '$canonical_name' (devcontainer-manifest: $manifest_name) in $registry"
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
