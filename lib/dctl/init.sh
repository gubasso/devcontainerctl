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

Register a project in the dctl project registry, pointing it to a shared
devcontainer template, then run the setup smoke test.

Options:
  --template <name>   Use a specific template
  --list              List available templates and exit
  --force             Re-register even if already registered
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
  local -A seen=()
  local templates=()
  shopt -s nullglob
  local dir name
  # User templates first (higher precedence)
  for dir in "${DCTL_CONFIG_DIR}/templates"/*/; do
    if [[ -f "${dir}devcontainer.json" ]]; then
      name="$(basename "$dir")"
      seen["$name"]=1
      templates+=("$name")
    fi
  done
  # Installed templates (skipped if user override exists)
  for dir in "$TEMPLATES_DIR"/*/; do
    if [[ -f "${dir}devcontainer.json" ]]; then
      name="$(basename "$dir")"
      if [[ -z "${seen[$name]:-}" ]]; then
        templates+=("$name")
      fi
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

template_path() {
  local user_path="${DCTL_CONFIG_DIR}/templates/$1/devcontainer.json"
  if [[ -f "$user_path" ]]; then
    printf '%s\n' "$user_path"
    return 0
  fi
  printf '%s/%s/devcontainer.json\n' "$TEMPLATES_DIR" "$1"
}

ensure_templates_dir_exists() {
  if [[ ! -d "$TEMPLATES_DIR" && ! -d "${DCTL_CONFIG_DIR}/templates" ]]; then
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

copy_template_to_workspace() {
  local template="$1"
  local source_path
  source_path="$(template_path "$template")"

  if [[ ! -f "$source_path" ]]; then
    printf 'Available templates:\n' >&2
    print_available_templates
    err "Unknown template: $template"
  fi

  mkdir -p "$(workspace_devcontainer_dir)"
  cp "$source_path" "$(workspace_devcontainer_file)"
}

template_registry_defaults() {
  local template="$1"
  case "$template" in
    base|coordinator) printf 'agents devimg/agents:latest\n' ;;
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

  if [[ -n "$existing_registry_path" && -f "$existing_registry_path" && "$force" != true ]]; then
    warn "Project '$canonical_name' already registered with config at $existing_registry_path; skipping"
    DCTL_CLI_CONFIG="$existing_registry_path" cmd_test
    return $?
  fi

  local local_config
  local_config="$(workspace_devcontainer_file)"
  if [[ -f "$local_config" && "$force" != true ]]; then
    warn "Existing devcontainer config found at $local_config; skipping"
    DCTL_CLI_CONFIG="$local_config" cmd_test
    return $?
  fi

  ensure_templates_dir_exists

  if [[ -z "$template" ]]; then
    template="$(select_template)" || return $?
  fi

  local shared_config
  shared_config="$(template_path "$template")"
  [[ -f "$shared_config" ]] || {
    printf 'Available templates:\n' >&2
    print_available_templates
    err "Unknown template: $template"
  }
  shared_config="$(realpath "$shared_config")"

  if [[ "$register" == true ]]; then
    local reg_dockerfile="" reg_image=""
    read -r reg_dockerfile reg_image < <(template_registry_defaults "$template") || true
    register_project_defaults "$canonical_name" "$shared_config" "$reg_dockerfile" "$reg_image"
  fi

  log "Project '$canonical_name' configured with template: $template"

  DCTL_CLI_CONFIG="$shared_config" cmd_test
}

main_init() {
  cmd_init "$@"
}
