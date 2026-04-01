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
source "${DCTL_LIB_DIR}/test.sh"

usage_init() {
  cat <<'EOF'
Usage: dctl init [options]

Deploy a devcontainer template and register the project in the dctl
project registry, then run the setup smoke test.

Options:
  --template <name>   Use a specific template
  --image-only        Seed the managed image only
  --devcontainer-only Deploy the devcontainer only
  --list              List available templates and exit
  --force             Rebuild cached merged config and re-register (preserves user config)
  --reset             Re-seed config from installed templates, rebuild cache, and re-register
  --no-register       Skip project registry registration
  --help, -h          Show this help text

Examples:
  dctl init --template python
  dctl init --image-only --template python
  dctl init --devcontainer-only --template python
  dctl init --list
  dctl init
  dctl init --force --template rust
  dctl init --reset --template rust
EOF
}

discover_templates() {
  local templates=()
  shopt -s nullglob
  local dir name
  for dir in "$DEVCONTAINERS_DIR"/*/; do
    if [[ -f "${dir}devcontainer.json" ]]; then
      name="$(basename "$dir")"
      # Skip internal templates (underscore prefix)
      [[ "$name" == _* ]] && continue
      templates+=("$name")
    fi
  done
  shopt -u nullglob

  printf '%s\n' "${templates[@]}"
}

print_available_templates() {
  local -a templates=()
  mapfile -t templates < <(discover_templates)

  if [[ ${#templates[@]} -eq 0 ]]; then
    printf '  (none found)\n' >&2
    return
  fi

  printf '  %s\n' "${templates[@]}" >&2
}

installed_template_path() {
  printf '%s/%s/devcontainer.json\n' "$DEVCONTAINERS_DIR" "$1"
}

ensure_templates_dir_exists() {
  if [[ ! -d "$DEVCONTAINERS_DIR" ]]; then
    err "No devcontainers directory found. Install with: make install"
  fi
}

select_template() {
  local available=()
  mapfile -t available < <(discover_templates)

  if [[ ${#available[@]} -eq 0 ]]; then
    err "No templates found in $DEVCONTAINERS_DIR"
  fi

  if ! command -v fzf >/dev/null 2>&1 || [[ ! -t 0 ]]; then
    printf 'Available templates:\n' >&2
    print_available_templates
    err "Pass --template <name> or run interactively with fzf installed."
  fi

  local selected
  if ! selected=$(printf '%s\n' "${available[@]}" | fzf \
    --height=~50% \
    --layout=reverse \
    --border \
    --prompt="Select template: " \
    --header="ENTER: confirm, ESC: cancel"); then
    return 1
  fi

  printf '%s\n' "$selected"
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

  # Validate each file individually so parse errors show correct file + line
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

discover_installed_layers() {
  local layers=()
  shopt -s nullglob
  local dir
  for dir in "$DEVCONTAINERS_DIR"/_*/; do
    if [[ -f "${dir}devcontainer.json" ]]; then
      layers+=("$(basename "$dir")")
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

_seed_config_file() {
  local source="$1"
  local dest="$2"
  local force="${3:-false}"

  if [[ -f "$dest" && "$force" != true ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  cp -p "$source" "$dest"
}

deploy_template_config() {
  local template="$1"
  local force="${2:-false}"
  local reset="${3:-false}"

  require_cmd jq

  local -a installed_layers=()
  mapfile -t installed_layers < <(discover_installed_layers)
  if [[ ${#installed_layers[@]} -eq 0 ]]; then
    err "No composable layers found in installed templates. Install with: make install"
  fi

  local layer_name
  for layer_name in "${installed_layers[@]}"; do
    local installed_layer config_layer
    installed_layer="$(installed_template_path "$layer_name")"
    [[ -f "$installed_layer" ]] || err "Composable layer not found: $layer_name"
    config_layer="$(config_devcontainer_path "$layer_name")"
    if [[ ! -f "$config_layer" ]] || [[ "$reset" == true ]]; then
      _seed_config_file "$installed_layer" "$config_layer" "$reset"
    fi
  done

  local config_tmpl
  config_tmpl="$(config_devcontainer_path "$template")"
  if [[ ! -f "$config_tmpl" ]] || [[ "$reset" == true ]]; then
    local installed_tmpl
    installed_tmpl="$(installed_template_path "$template")"
    if [[ ! -f "$installed_tmpl" ]]; then
      print_available_templates
      err "Unknown template: $template"
    fi
    _seed_config_file "$installed_tmpl" "$config_tmpl" "$reset"
  fi

  local cached_path
  cached_path="$(deployed_devcontainer_path "$template")"

  local -a config_layers=()
  mapfile -t config_layers < <(discover_config_layers)
  if [[ ${#config_layers[@]} -eq 0 ]]; then
    err "No composable config layers found in ${DCTL_DEVCONTAINER_DIR}. Add an _NN-* layer or run dctl init after make install."
  fi

  if [[ "$force" != true && "$reset" != true ]] && cache_is_fresh "$cached_path" "${config_layers[@]}" "$config_tmpl"; then
    log "Using cached config: $cached_path" >&2
    printf '%s\n' "$cached_path"
    printf 'cached\n'
    return 0
  fi

  mkdir -p "$(dirname "$cached_path")"
  local tmp_path
  tmp_path="$(mktemp "${cached_path}.tmp.XXXXXX")"

  local tmp_acc
  tmp_acc="$(mktemp "${cached_path}.layers.XXXXXX")"
  cp "${config_layers[0]}" "$tmp_acc"

  local layer_path
  for layer_path in "${config_layers[@]:1}"; do
    local tmp_next
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
  log "Generated config for '$template' at $cached_path" >&2
  printf '%s\n' "$cached_path"
  printf 'generated\n'
}

deploy_image_config() {
  local image_name="$1"
  local reset="${2:-false}"

  local installed_dir="${IMAGES_DIR}/${image_name}"
  [[ -d "$installed_dir" ]] || return 0

  local config_dir="${DCTL_IMAGES_DIR}/${image_name}"

  shopt -s nullglob
  local file
  for file in "$installed_dir"/*; do
    [[ -f "$file" ]] || continue
    local dest
    dest="${config_dir}/$(basename "$file")"
    if [[ ! -f "$dest" ]] || [[ "$reset" == true ]]; then
      _seed_config_file "$file" "$dest" "$reset"
    fi
  done
  shopt -u nullglob
}

template_registry_defaults() {
  local template="$1"
  case "$template" in
    general|coordinator) printf 'agents devimg/agents:latest\n' ;;
    python)           printf 'python-dev devimg/python-dev:latest\n' ;;
    rust)             printf 'rust-dev devimg/rust-dev:latest\n' ;;
    zig)              printf 'zig-dev devimg/zig-dev:latest\n' ;;
    *)                printf '\n' ;;
  esac
}

cmd_init() {
  local template=""
  local force=false
  local reset=false
  local list=false
  local register=true
  local image_only=false
  local devcontainer_only=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --template)
        [[ $# -ge 2 ]] || err "--template requires a value"
        template="$2"
        shift 2
        ;;
      --list)
        list=true
        shift
        ;;
      --image-only)
        image_only=true
        shift
        ;;
      --devcontainer-only)
        devcontainer_only=true
        shift
        ;;
      --force)
        force=true
        shift
        ;;
      --reset)
        reset=true
        shift
        ;;
      --no-register)
        register=false
        shift
        ;;
      --help | -h)
        usage_init
        return 0
        ;;
      *)
        err "Unknown init option: $1"
        ;;
    esac
  done

  if [[ "$list" == true ]]; then
    discover_templates
    return 0
  fi

  if [[ "$image_only" == true && "$devcontainer_only" == true ]]; then
    err "Cannot use --image-only with --devcontainer-only"
  fi

  local do_image=true
  local do_devcontainer=true
  if [[ "$image_only" == true ]]; then
    do_devcontainer=false
  elif [[ "$devcontainer_only" == true ]]; then
    do_image=false
  fi

  # Check if project already has config (registry or local)
  local canonical_name
  canonical_name="$(resolve_canonical_project_name)"

  local existing_registry_path=""
  if command -v yq >/dev/null 2>&1; then
    existing_registry_path="$(_registry_lookup_devcontainer "$canonical_name")"
  fi

  local registry_force=false
  local deploy_force="$force"
  if [[ "$force" == true || "$reset" == true ]]; then
    registry_force=true
  fi

  if [[ "$do_devcontainer" == true ]]; then
    if [[ -n "$existing_registry_path" && "$force" != true && "$reset" != true ]]; then
      # If user explicitly requested a different template, skip short-circuit
      local registered_template_name=""
      if [[ -f "$existing_registry_path" && "$existing_registry_path" == "${DCTL_DEVCONTAINER_CACHE_DIR}/"* ]]; then
        registered_template_name="$(basename "$(dirname "$existing_registry_path")")"
      fi
      if [[ -n "$template" && -n "$registered_template_name" && "$template" != "$registered_template_name" ]]; then
        warn "Switching project '$canonical_name' from template '$registered_template_name' to '$template'"
        registry_force=true
      elif [[ -f "$existing_registry_path" ]]; then
        if [[ "$existing_registry_path" == "${DCTL_DEVCONTAINER_CACHE_DIR}/"* ]]; then
          # Cache path — refresh if stale
          local registered_template
          registered_template="$(basename "$(dirname "$existing_registry_path")")"
          local refreshed_output refreshed_path
          refreshed_output="$(deploy_template_config "$registered_template" false false)" || return $?
          refreshed_path="$(head -1 <<< "$refreshed_output")"
          # shellcheck disable=SC2034
          DCTL_CONFIG_STATUS="$(tail -1 <<< "$refreshed_output")"
          DCTL_CLI_CONFIG="$refreshed_path" cmd_test
          return $?

        elif [[ "$existing_registry_path" == "${DCTL_DEVCONTAINER_DIR}/"* ]]; then
          # Legacy config path — migrate to cache
          local registered_template
          registered_template="$(basename "$(dirname "$existing_registry_path")")"
          warn "Migrating legacy config path to cache for template '$registered_template'"
          local migrate_output migrate_path
          migrate_output="$(deploy_template_config "$registered_template" false false)" || return $?
          migrate_path="$(head -1 <<< "$migrate_output")"
          # shellcheck disable=SC2034
          DCTL_CONFIG_STATUS="$(tail -1 <<< "$migrate_output")"
          # Update only the devcontainer field, preserving dockerfile/image/sibling_discovery
          _registry_update_devcontainer "$canonical_name" "$migrate_path"
          DCTL_CLI_CONFIG="$migrate_path" cmd_test
          return $?

        else
          # External path — use as-is
          # shellcheck disable=SC2034
          DCTL_CONFIG_STATUS="existing"
          warn "Project '$canonical_name' already registered with config at $existing_registry_path; skipping"
          DCTL_CLI_CONFIG="$existing_registry_path" cmd_test
          return $?
        fi
      fi
      if [[ ! -f "$existing_registry_path" ]]; then
        # Registry entry exists but path is stale — force registry update only
        warn "Registered config path no longer exists: $existing_registry_path; re-deploying"
        registry_force=true
        deploy_force=true
      fi
    fi
  fi

  ensure_templates_dir_exists

  if [[ -z "$template" ]]; then
    template="$(select_template)" || return $?
  fi

  # Validate template exists even for image-only (needed for registry defaults lookup)
  if [[ "$image_only" == true ]]; then
    local installed_tmpl
    installed_tmpl="$(installed_template_path "$template")"
    if [[ ! -f "$installed_tmpl" ]]; then
      print_available_templates
      err "Unknown template: $template"
    fi
  fi

  local reg_dockerfile="" reg_image=""
  read -r reg_dockerfile reg_image < <(template_registry_defaults "$template") || true

  if [[ "$do_image" == true ]]; then
    if [[ -n "$reg_dockerfile" ]]; then
      deploy_image_config "$reg_dockerfile" "$reset"
      log "Image '$reg_dockerfile' seeded to ${DCTL_IMAGES_DIR}/${reg_dockerfile}/"
    fi
  fi

  local deployed_config=""
  if [[ "$do_devcontainer" == true ]]; then
    local deploy_output
    deploy_output="$(deploy_template_config "$template" "$deploy_force" "$reset")" || return $?
    deployed_config="$(head -1 <<< "$deploy_output")"
    # shellcheck disable=SC2034
    DCTL_CONFIG_STATUS="$(tail -1 <<< "$deploy_output")"
  fi

  if [[ "$register" == true ]]; then
    if [[ "$do_devcontainer" == true ]]; then
      register_project_defaults "$canonical_name" "$deployed_config" "$reg_dockerfile" "$reg_image" "$registry_force"
    elif [[ "$image_only" == true ]]; then
      if [[ -z "$existing_registry_path" ]]; then
        warn "No existing devcontainer found in project registry; registering image metadata only"
      fi
      register_project_defaults "$canonical_name" "$existing_registry_path" "$reg_dockerfile" "$reg_image" "$registry_force"
    fi
  fi

  log "Project '$canonical_name' configured with template: $template"

  if [[ "$do_devcontainer" == true ]]; then
    DCTL_CLI_CONFIG="$deployed_config" cmd_test
  fi
}

main_init() {
  cmd_init "$@"
}
