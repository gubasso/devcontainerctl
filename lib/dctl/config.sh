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
      # --force-filetype yaml: never infer the parser from the path (see the
      # matching note in _validate_registry).
      if ! validation_output="$(check-jsonschema --force-filetype yaml --schemafile "$schema" "$manifest" 2>&1)"; then
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

_strip_jsonc_comments() {
  sed '/^[[:space:]]*\/\//d' "$1"
}

merge_two_configs() {
  local base_path="$1"
  local template_path="$2"

  local base_json tmpl_json jq_err

  base_json="$(_strip_jsonc_comments "$base_path")" || return 1
  tmpl_json="$(_strip_jsonc_comments "$template_path")" || return 1

  if ! jq_err="$(jq empty <<<"$base_json" 2>&1)"; then
    printf 'JSON syntax error in %s:\n  %s\n' "$base_path" "$jq_err" >&2
    return 1
  fi
  if ! jq_err="$(jq empty <<<"$tmpl_json" 2>&1)"; then
    printf 'JSON syntax error in %s:\n  %s\n' "$template_path" "$jq_err" >&2
    return 1
  fi

  jq -s '
    .[0] as $base | .[1] as $tmpl |
    $base * $tmpl |
    .mounts = (($base.mounts // []) + ($tmpl.mounts // [])) |
    .postCreateCommand = (($base.postCreateCommand // {}) * ($tmpl.postCreateCommand // {})) |
    .containerEnv = (($base.containerEnv // {}) * ($tmpl.containerEnv // {})) |
    .remoteEnv = (($base.remoteEnv // {}) * ($tmpl.remoteEnv // {}))
  ' <(echo "$base_json") <(echo "$tmpl_json")
}

_validate_deployed_devcontainer() {
  local template="$1"
  local manifest
  manifest="$(config_compose_manifest_path "$template")"
  [[ -f $manifest ]] || err "Unknown deployed devcontainer: $template (no manifest at $manifest)"
}

discover_config_layers() {
  local config_name="$1"
  local manifest
  manifest="$(config_compose_manifest_path "$config_name")"

  [[ -f $manifest ]] || err "No manifest found for '$config_name' at $manifest"
  _validate_compose_manifest "$manifest"

  local -a layers=()
  local layer_name layer_path
  while IFS= read -r layer_name; do
    [[ -n $layer_name ]] || continue
    layer_path="${DCTL_DEVCONTAINER_DIR}/${layer_name}/devcontainer.json"
    [[ -f $layer_path ]] || err "Layer '$layer_name' referenced in manifest '$config_name' not found: $layer_path"
    layers+=("$layer_path")
  done < <(_read_manifest_layers "$manifest")

  [[ ${#layers[@]} -gt 0 ]] || err "No layers found in manifest for '$config_name'"
  printf '%s\n' "${layers[@]}"
}

# Merge a deployed devcontainer's manifest layers into a single config and
# write it to the runtime generated path, freshly, every call — there is no
# cache and no freshness check. Echoes the generated path.
generate_devcontainer() {
  local template="$1"

  require_cmd jq
  _validate_deployed_devcontainer "$template"

  local gen_path
  gen_path="$(devcontainer_generated_path_for_manifest "$template")"

  local -a config_layers=()
  mapfile -t config_layers < <(discover_config_layers "$template")
  if [[ ${#config_layers[@]} -eq 0 ]]; then
    err "No composable config layers found for ${template}. Run: dctl deploy devcontainer ${template}"
  fi

  mkdir -p "$(dirname "$gen_path")"
  local tmp_path tmp_acc
  tmp_path="$(mktemp "${gen_path}.tmp.XXXXXX")"
  tmp_acc="$(mktemp "${gen_path}.layers.XXXXXX")"
  cp "${config_layers[0]}" "$tmp_acc"

  local layer_path tmp_next
  for layer_path in "${config_layers[@]:1}"; do
    tmp_next="$(mktemp "${gen_path}.layers.XXXXXX")"
    if ! merge_two_configs "$tmp_acc" "$layer_path" >"$tmp_next"; then
      rm -f "$tmp_path" "$tmp_acc" "$tmp_next"
      err "Failed to merge layer '$layer_path' for '$template'"
    fi
    rm -f "$tmp_acc"
    tmp_acc="$tmp_next"
  done

  mv "$tmp_acc" "$tmp_path"
  mv "$tmp_path" "$gen_path"
  printf '%s\n' "$gen_path"
}

# Override the common.sh stub so resolve_devcontainer_config regenerates.
_generate_devcontainer_impl() {
  generate_devcontainer "$@"
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
      # --force-filetype yaml: check-jsonschema picks its parser from the
      # instance's extension, so a caller passing a temp path (see
      # register_project_defaults) would otherwise be parsed as JSON and fail
      # with a JSONDecodeError. The registry is always YAML regardless of name.
      if ! validation_output="$(check-jsonschema --force-filetype yaml --schemafile "$schema" "$registry" 2>&1)"; then
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

  require_cmd yq
  _registry_ensure_file

  local registry
  registry="$(_registry_file)"

  # Lenient pre-write check only: the migration step below scrubs legacy keys
  # that strict validation would reject, and _validate_registry runs after the
  # write to enforce the final shape.
  if [[ -s $registry ]]; then
    if ! yq eval '.' "$registry" >/dev/null 2>&1; then
      err "Invalid YAML in $registry"
    fi
  fi

  # Use env vars to pass values safely to yq (avoids injection via special chars).
  # Preserve an explicit sibling_discovery for this project across re-registration.
  local existing_sibling="true"
  if _registry_has_project "$canonical_name"; then
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
  # Migrate legacy keys registry-wide so a normal init also upgrades an old
  # registry in one shot. For each entry that still has a legacy `devcontainer:`
  # path of the form `<...>/<manifest>/devcontainer.json` (the only shape the
  # prior contract emitted), derive `devcontainer-manifest` from
  # basename(dirname(path)) when the manifest field is not already set. Then
  # drop the legacy `devcontainer`, `dockerfile`, and `image` keys. Entries that
  # have neither key are left untouched. Any derived manifest name that does not
  # match the schema pattern is caught by the post-write _validate_registry call.
  yq_expr+=' | with_entries(.value |= ('
  yq_expr+='(.["devcontainer-manifest"] = ('
  yq_expr+='(.["devcontainer-manifest"] // (.["devcontainer"] | sub("/devcontainer\.json$"; "") | sub("^.*/"; "")))'
  yq_expr+=')) | ('
  yq_expr+='select(.["devcontainer-manifest"] == null or .["devcontainer-manifest"] == "") '
  yq_expr+='| del(.["devcontainer-manifest"])'
  yq_expr+=') // . '
  yq_expr+='| del(.["devcontainer"]) | del(.dockerfile) | del(.image)'
  yq_expr+='))'

  # Keep the .yaml suffix on the candidate: tooling that infers a file's format
  # from its extension must see YAML here, not a `.tmp.<pid>` tail.
  local tmp_registry="${registry%.yaml}.tmp.$$.yaml"
  export YQ_KEY="$canonical_name" YQ_MANIFEST="$manifest_name"
  if [[ -s $registry ]]; then
    yq eval "$yq_expr" "$registry" >"$tmp_registry"
  else
    yq -n "$yq_expr" >"$tmp_registry"
  fi
  unset YQ_KEY YQ_MANIFEST

  # Validate the migrated candidate before it replaces the live registry so
  # genuinely-invalid input fails closed and leaves projects.yaml untouched.
  # _validate_registry calls `err` (which exits) on failure, so run it in a
  # subshell to catch the result, clean up the temp file, and re-emit the
  # message without having mutated the user's registry.
  local validation_output
  if ! validation_output="$(_validate_registry "$tmp_registry" 2>&1)"; then
    rm -f "$tmp_registry"
    # Map the temp path back to the real registry in the surfaced message.
    err "${validation_output//"$tmp_registry"/"$registry"}"
  fi

  mv "$tmp_registry" "$registry"

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
