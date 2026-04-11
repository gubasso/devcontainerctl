# shellcheck shell=bash
# Init command for dctl (sourced, not executed directly)

[[ -n "${_DCTL_INIT_LOADED:-}" ]] && return 0
readonly _DCTL_INIT_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/common.sh"
# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/config.sh"
# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/image.sh"
# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/test.sh"

usage_init() {
  cat <<'EOF'
Usage: dctl init [options]

Register the current project against a deployed devcontainer config and run
the workspace smoke test.

Options:
  --devcontainer <name>                Use a specific deployed devcontainer
  --force                              Rebuild cached merged config and re-register
  --help, -h                           Show this help text

Examples:
  dctl init --devcontainer python
  dctl init --force --devcontainer rust
  dctl init
EOF
}

_discover_deployed_selectable_devcontainers() {
  local templates=()
  shopt -s nullglob
  local dir name
  for dir in "$DCTL_DEVCONTAINER_DIR"/*/; do
    [[ -f "${dir}devcontainer.json" ]] || continue
    name="$(basename "$dir")"
    [[ "$name" == _* ]] && continue
    templates+=("$name")
  done
  shopt -u nullglob
  [[ ${#templates[@]} -gt 0 ]] && printf '%s\n' "${templates[@]}"
}

_select_deployed_devcontainer_interactive() {
  local -a available=()
  mapfile -t available < <(_discover_deployed_selectable_devcontainers)

  [[ ${#available[@]} -gt 0 ]] || err "No devcontainers deployed. Run: dctl deploy (or dctl deploy devcontainer <name>)"
  command -v fzf >/dev/null 2>&1 || err "fzf not found. Install fzf or pass --devcontainer <name>."
  [[ -t 0 ]] || err "Interactive init requires a terminal. Pass --devcontainer <name>."

  printf '%s\n' "${available[@]}" | _fzf_pick \
    "Select deployed devcontainer: " \
    "ENTER: confirm, ESC: cancel"
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

  if ! jq_err="$(jq empty <<< "$base_json" 2>&1)"; then
    printf 'JSON syntax error in %s:\n  %s\n' "$base_path" "$jq_err" >&2
    return 1
  fi
  if ! jq_err="$(jq empty <<< "$tmpl_json" 2>&1)"; then
    printf 'JSON syntax error in %s:\n  %s\n' "$template_path" "$jq_err" >&2
    return 1
  fi

  jq -s '
    .[0] as $base | .[1] as $tmpl |
    $base * $tmpl |
    .mounts = (($base.mounts // []) + ($tmpl.mounts // [])) |
    .postCreateCommand = (($base.postCreateCommand // {}) * ($tmpl.postCreateCommand // {})) |
    .containerEnv = (($base.containerEnv // {}) * ($tmpl.containerEnv // {}))
  ' <(echo "$base_json") <(echo "$tmpl_json")
}

discover_config_layers() {
  local layers=()
  shopt -s nullglob
  local dir
  for dir in "$DCTL_DEVCONTAINER_DIR"/_*/; do
    if [[ -f "${dir}devcontainer.json" ]]; then
      layers+=("${dir}devcontainer.json")
    fi
  done
  shopt -u nullglob
  [[ ${#layers[@]} -gt 0 ]] && printf '%s\n' "${layers[@]}"
}

cache_is_fresh() {
  local cached_path="$1"
  shift
  [[ -f "$cached_path" ]] || return 1
  local source_path
  for source_path in "$@"; do
    [[ "$cached_path" -nt "$source_path" ]] || return 1
  done
}

_validate_deployed_devcontainer() {
  local template="$1"
  local config_tmpl
  config_tmpl="$(config_devcontainer_path "$template")"
  [[ -f "$config_tmpl" ]] || err "Unknown deployed devcontainer: $template"
}

_infer_image_from_devcontainer_json() {
  local path="$1"
  local json jq_err

  require_cmd jq
  json="$(_strip_jsonc_comments "$path")" || return 1
  if ! jq_err="$(jq empty <<< "$json" 2>&1)"; then
    printf 'JSON syntax error in %s:\n  %s\n' "$path" "$jq_err" >&2
    return 1
  fi

  jq -r '.image // empty' <<< "$json"
}

_image_ref_to_name() {
  local image_ref="$1"
  if [[ "$image_ref" =~ ^devimg/([[:alnum:]._-]+):latest$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

generate_cached_devcontainer() {
  local template="$1"
  local force="${2:-false}"

  require_cmd jq
  _validate_deployed_devcontainer "$template"

  local config_tmpl cached_path
  config_tmpl="$(config_devcontainer_path "$template")"
  cached_path="$(deployed_devcontainer_path "$template")"

  local -a config_layers=()
  mapfile -t config_layers < <(discover_config_layers)
  if [[ ${#config_layers[@]} -eq 0 ]]; then
    err "No composable config layers found in ${DCTL_DEVCONTAINER_DIR}. Run: dctl deploy devcontainer ${template}"
  fi

  if [[ "$force" != true ]] && cache_is_fresh "$cached_path" "${config_layers[@]}" "$config_tmpl"; then
    printf '%s\n' "$cached_path"
    printf 'cached\n'
    return 0
  fi

  mkdir -p "$(dirname "$cached_path")"
  local tmp_path tmp_acc
  tmp_path="$(mktemp "${cached_path}.tmp.XXXXXX")"
  tmp_acc="$(mktemp "${cached_path}.layers.XXXXXX")"
  cp "${config_layers[0]}" "$tmp_acc"

  local layer_path tmp_next
  for layer_path in "${config_layers[@]:1}"; do
    tmp_next="$(mktemp "${cached_path}.layers.XXXXXX")"
    if ! merge_two_configs "$tmp_acc" "$layer_path" > "$tmp_next"; then
      rm -f "$tmp_path" "$tmp_acc" "$tmp_next"
      err "Failed to merge composable layer '$layer_path' for '$template'"
    fi
    rm -f "$tmp_acc"
    tmp_acc="$tmp_next"
  done

  if ! merge_two_configs "$tmp_acc" "$config_tmpl" > "$tmp_path"; then
    rm -f "$tmp_path" "$tmp_acc"
    err "Failed to merge config layers and template for '$template'"
  fi
  rm -f "$tmp_acc"

  mv "$tmp_path" "$cached_path"
  printf '%s\n' "$cached_path"
  printf 'generated\n'
}

ensure_image_available_for_devcontainer() {
  local devcontainer_name="$1"
  local config_path cached_path image_ref image_name

  DCTL_INIT_IMAGE_STATUS=""
  DCTL_INIT_IMAGE_REF=""

  cached_path="$(deployed_devcontainer_path "$devcontainer_name")"
  config_path="$(config_devcontainer_path "$devcontainer_name")"
  if [[ -f "$cached_path" ]]; then
    image_ref="$(_infer_image_from_devcontainer_json "$cached_path" || true)"
  else
    image_ref="$(_infer_image_from_devcontainer_json "$config_path" || true)"
  fi

  DCTL_INIT_IMAGE_REF="$image_ref"
  if [[ -z "$image_ref" ]]; then
    DCTL_INIT_IMAGE_STATUS="no-image"
    return 0
  fi

  if ! image_name="$(_image_ref_to_name "$image_ref" 2>/dev/null)"; then
    DCTL_INIT_IMAGE_STATUS="external"
    log "Using external image from deployed config: $image_ref"
    return 0
  fi

  if [[ ! -f "$(config_image_path "$image_name")" ]]; then
    err "Image '$image_name' is not deployed. Run: dctl deploy image $image_name"
  fi

  require_cmd docker
  if docker image inspect "$image_ref" >/dev/null 2>&1; then
    DCTL_INIT_IMAGE_STATUS="already-built"
    return 0
  fi

  cmd_image_build "$image_name"
  DCTL_INIT_IMAGE_STATUS="built-now"
}

cmd_init() {
  local devcontainer=""
  local force=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --devcontainer)
        [[ $# -ge 2 ]] || err "--devcontainer requires a value"
        devcontainer="$2"
        shift 2
        ;;
      --force)
        force=true
        shift
        ;;
      --help|-h)
        usage_init
        return 0
        ;;
      *)
        err "Unknown init option: $1"
        ;;
    esac
  done

  local -a available=()
  mapfile -t available < <(_discover_deployed_selectable_devcontainers)
  [[ ${#available[@]} -gt 0 ]] || err "No devcontainers deployed. Run: dctl deploy (or dctl deploy devcontainer <name>)"

  if [[ -z "$devcontainer" ]]; then
    devcontainer="$(_select_deployed_devcontainer_interactive)" || return $?
  fi

  _validate_deployed_devcontainer "$devcontainer"

  local canonical_name existing_registry_path registry_force=false
  canonical_name="$(resolve_canonical_project_name)"

  if command -v yq >/dev/null 2>&1; then
    existing_registry_path="$(_registry_lookup_devcontainer "$canonical_name")"
  else
    existing_registry_path=""
  fi

  if [[ "$force" == true ]]; then
    registry_force=true
  elif [[ -n "$existing_registry_path" ]]; then
    if [[ ! -f "$existing_registry_path" ]]; then
      warn "Registered config path no longer exists: $existing_registry_path; re-registering"
      registry_force=true
    elif [[ "$existing_registry_path" == "${DCTL_DEVCONTAINER_CACHE_DIR}/"* ]]; then
      local registered_template_name
      registered_template_name="$(basename "$(dirname "$existing_registry_path")")"
      if [[ -n "$registered_template_name" && "$registered_template_name" != "$devcontainer" ]]; then
        warn "Switching project '$canonical_name' from template '$registered_template_name' to '$devcontainer'"
        registry_force=true
      fi
    fi
  fi

  local cache_output deployed_config config_status
  cache_output="$(generate_cached_devcontainer "$devcontainer" "$force")" || return $?
  deployed_config="$(head -1 <<< "$cache_output")"
  config_status="$(tail -1 <<< "$cache_output")"

  ensure_image_available_for_devcontainer "$devcontainer"

  register_project_defaults "$canonical_name" "$deployed_config" "$registry_force"

  local test_status="passed"
  if ! DCTL_CLI_CONFIG="$deployed_config" cmd_test; then
    test_status="failed"
  fi

  log ""
  log "=== dctl init summary ==="
  log "Project: $canonical_name"
  log "Devcontainer: $devcontainer"
  case "${DCTL_INIT_IMAGE_STATUS:-}" in
    already-built)
      log "Image status: already-built (${DCTL_INIT_IMAGE_REF})"
      ;;
    built-now)
      log "Image status: built-now (${DCTL_INIT_IMAGE_REF})"
      ;;
    external)
      log "Image status: external (${DCTL_INIT_IMAGE_REF})"
      ;;
    no-image)
      log "Image status: no image declared"
      ;;
  esac
  log "Cache path: $deployed_config"
  log "Cache status: $config_status"
  log "Registry path: ${DCTL_CONFIG_DIR}/projects.yaml"
  log "Smoke test: $test_status"

  [[ "$test_status" == "passed" ]] || return 1
}

main_init() {
  cmd_init "$@"
}
