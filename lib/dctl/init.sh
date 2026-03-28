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
  --list              List available templates and exit
  --force             Re-deploy template and update registry even if already configured
  --no-register       Skip project registry registration
  --help, -h          Show this help text

Examples:
  dctl init --template python
  dctl init --list
  dctl init
  dctl init --force --template rust
EOF
}

discover_templates() {
  local templates=()
  shopt -s nullglob
  local dir name
  for dir in "$TEMPLATES_DIR"/*/; do
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
  printf '%s/%s/devcontainer.json\n' "$TEMPLATES_DIR" "$1"
}

ensure_templates_dir_exists() {
  if [[ ! -d "$TEMPLATES_DIR" ]]; then
    err "No templates directory found. Install with: make install"
  fi
}

select_template() {
  local available=()
  mapfile -t available < <(discover_templates)

  if [[ ${#available[@]} -eq 0 ]]; then
    err "No templates found in $TEMPLATES_DIR"
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

  jq -s '
    .[0] as $base | .[1] as $tmpl |
    $base * $tmpl |
    .mounts = (($base.mounts // []) + ($tmpl.mounts // [])) |
    .postCreateCommand = (($base.postCreateCommand // {}) * ($tmpl.postCreateCommand // {})) |
    .containerEnv = (($base.containerEnv // {}) * ($tmpl.containerEnv // {}))
  ' <(_strip_jsonc_comments "$base_path") <(_strip_jsonc_comments "$template_path")
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
  for dir in "$TEMPLATES_DIR"/_*/; do
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
  cp "$source" "$dest"
}

deploy_template_config() {
  local template="$1"
  local force="${2:-false}"

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
    if [[ ! -f "$config_layer" ]] || [[ "$force" == true ]]; then
      _seed_config_file "$installed_layer" "$config_layer" "$force"
    fi
  done

  local config_tmpl
  config_tmpl="$(config_devcontainer_path "$template")"
  if [[ ! -f "$config_tmpl" ]] || [[ "$force" == true ]]; then
    local installed_tmpl
    installed_tmpl="$(installed_template_path "$template")"
    if [[ ! -f "$installed_tmpl" ]]; then
      print_available_templates
      err "Unknown template: $template"
    fi
    _seed_config_file "$installed_tmpl" "$config_tmpl" "$force"
  fi

  local cached_path
  cached_path="$(deployed_devcontainer_path "$template")"

  local -a config_layers=()
  mapfile -t config_layers < <(discover_config_layers)
  if [[ ${#config_layers[@]} -eq 0 ]]; then
    err "No composable config layers found in ${DCTL_DEVCONTAINER_DIR}. Add an _NN-* layer or run dctl init after make install."
  fi

  if [[ "$force" != true ]] && cache_is_fresh "$cached_path" "${config_layers[@]}" "$config_tmpl"; then
    log "Using cached config: $cached_path" >&2
    printf '%s\n' "$cached_path"
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
  local list=false
  local register=true

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
      --force)
        force=true
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

  # Check if project already has config (registry or local)
  local canonical_name
  canonical_name="$(resolve_canonical_project_name)"

  local existing_registry_path=""
  if command -v yq >/dev/null 2>&1; then
    existing_registry_path="$(_registry_lookup_devcontainer "$canonical_name")"
  fi

  local registry_force="$force"
  if [[ -n "$existing_registry_path" && "$force" != true ]]; then
    if [[ -f "$existing_registry_path" ]]; then
      # If path is inside our cache dir, refresh cache from config if stale
      if [[ "$existing_registry_path" == "${DCTL_DEVCONTAINER_CACHE_DIR}/"* ]]; then
        local registered_template
        registered_template="$(basename "$(dirname "$existing_registry_path")")"
        local refreshed_path
        refreshed_path="$(deploy_template_config "$registered_template" false)" || return $?
        DCTL_CLI_CONFIG="$refreshed_path" cmd_test
      else
        warn "Project '$canonical_name' already registered with config at $existing_registry_path; skipping"
        DCTL_CLI_CONFIG="$existing_registry_path" cmd_test
      fi
      return $?
    fi
    # Registry entry exists but path is stale — force registry update only
    warn "Registered config path no longer exists: $existing_registry_path; re-deploying"
    registry_force=true
  fi

  ensure_templates_dir_exists

  if [[ -z "$template" ]]; then
    template="$(select_template)" || return $?
  fi

  local deployed_config
  deployed_config="$(deploy_template_config "$template" "$force")" || return $?

  if [[ "$register" == true ]]; then
    local reg_dockerfile="" reg_image=""
    read -r reg_dockerfile reg_image < <(template_registry_defaults "$template") || true
    register_project_defaults "$canonical_name" "$deployed_config" "$reg_dockerfile" "$reg_image" "$registry_force"
  fi

  log "Project '$canonical_name' configured with template: $template"

  DCTL_CLI_CONFIG="$deployed_config" cmd_test
}

main_init() {
  cmd_init "$@"
}
