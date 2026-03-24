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

deploy_template_config() {
  local template="$1"
  local force="${2:-false}"
  local source_path
  source_path="$(installed_template_path "$template")"

  if [[ ! -f "$source_path" ]]; then
    printf 'Available templates:\n' >&2
    print_available_templates
    err "Unknown template: $template"
  fi

  local deployed_path
  deployed_path="$(deployed_devcontainer_path "$template")"

  if [[ -f "$deployed_path" && "$force" != true ]]; then
    log "Using existing deployed config: $deployed_path" >&2
    printf '%s\n' "$deployed_path"
    return 0
  fi

  mkdir -p "$(dirname "$deployed_path")"
  cp "$source_path" "$deployed_path"
  log "Deployed template '$template' to $deployed_path" >&2
  printf '%s\n' "$deployed_path"
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

  local registry_force="$force"
  if [[ -n "$existing_registry_path" && "$force" != true ]]; then
    if [[ -f "$existing_registry_path" ]]; then
      warn "Project '$canonical_name' already registered with config at $existing_registry_path; skipping"
      DCTL_CLI_CONFIG="$existing_registry_path" cmd_test
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
