# shellcheck shell=bash
# Shared primitives for dctl modules (sourced, not executed directly)

[[ -n "${_DCTL_COMMON_LOADED:-}" ]] && return 0
readonly _DCTL_COMMON_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"
: "${DCTL_VERSION:=dev}"
: "${WORKSPACE_FOLDER:=$PWD}"
WORKSPACE_FOLDER="$(cd -- "$WORKSPACE_FOLDER" && pwd -P)"
: "${IMAGES_DIR:=${XDG_DATA_HOME:-$HOME/.local/share}/dctl/images}"
: "${TEMPLATES_DIR:=${XDG_DATA_HOME:-$HOME/.local/share}/dctl/templates}"
: "${DCTL_CONFIG_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/dctl}"

readonly DCTL_VERSION
readonly WORKSPACE_FOLDER
readonly IMAGES_DIR
readonly TEMPLATES_DIR
readonly DCTL_CONFIG_DIR

log() {
  printf '\033[1;34m==>\033[0m %s\n' "$1"
}

warn() {
  printf '\033[1;33mWARN:\033[0m %s\n' "$1" >&2
}

err() {
  printf '\033[1;31mERROR:\033[0m %s\n' "$1" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || err "Missing required command: $cmd"
}

workspace_path() {
  printf '%s\n' "$WORKSPACE_FOLDER"
}

workspace_devcontainer_dir() {
  printf '%s/.devcontainer\n' "$WORKSPACE_FOLDER"
}

workspace_devcontainer_file() {
  printf '%s/devcontainer.json\n' "$(workspace_devcontainer_dir)"
}

workspace_label_filter() {
  printf 'label=devcontainer.local_folder=%s' "$(workspace_path)"
}

resolve_canonical_project_name() {
  local remote_url=""
  local remote_path=""
  local workspace_basename
  local canonical_name

  if command -v git >/dev/null 2>&1; then
    remote_url="$(git -C "$WORKSPACE_FOLDER" remote get-url origin 2>/dev/null || true)"
  fi

  if [[ -n "$remote_url" ]]; then
    if [[ "$remote_url" == *://* ]]; then
      remote_path="${remote_url#*://}"
      remote_path="${remote_path#*/}"
    elif [[ "$remote_url" == *:* ]]; then
      remote_path="${remote_url#*:}"
    else
      remote_path="$remote_url"
    fi

    remote_path="${remote_path%.git}"
    remote_path="${remote_path#/}"
    printf '%s\n' "${remote_path//\//-}"
    return 0
  fi

  workspace_basename="$(basename "$WORKSPACE_FOLDER")"
  canonical_name="$workspace_basename"
  if [[ "$workspace_basename" == *.* ]]; then
    canonical_name="${workspace_basename%%.*}"
  fi

  printf '%s\n' "$canonical_name"
}

_registry_lookup_devcontainer() {
  # Stub — returns empty. Phase 3 replaces with real yq-based lookup.
  return 0
}

_registry_lookup_sibling_discovery() {
  # Stub — returns "true" (default). Phase 3 replaces with real lookup.
  printf 'true\n'
}

resolve_work_clone_sibling() {
  require_cmd realpath

  local canonical_name
  canonical_name="$(resolve_canonical_project_name)"

  local sibling_discovery
  sibling_discovery="$(_registry_lookup_sibling_discovery "$canonical_name")"
  [[ "$sibling_discovery" == "true" ]] || return 0

  local workspace_basename
  workspace_basename="$(basename "$WORKSPACE_FOLDER")"
  [[ "$workspace_basename" == *.* ]] || return 0

  local main_repo_name
  main_repo_name="${workspace_basename%%.*}"

  local parent_dir
  parent_dir="$(dirname "$WORKSPACE_FOLDER")"

  local candidate_path
  candidate_path="${parent_dir}/${main_repo_name}"
  [[ -d "$candidate_path" ]] || return 0

  candidate_path="$(realpath "$candidate_path")"
  [[ "$candidate_path" != "$WORKSPACE_FOLDER" ]] || return 0
  [[ -d "$candidate_path/.git" ]] || return 0

  local candidate_config
  candidate_config="${candidate_path}/.devcontainer/devcontainer.json"
  [[ -f "$candidate_config" ]] || return 0

  realpath "$candidate_config"
}

resolve_devcontainer_config() {
  require_cmd realpath

  local config_path
  local canonical_name
  local registry_path
  local local_path
  local sibling_path
  local default_path

  if [[ -n "${DCTL_CLI_CONFIG:-}" ]]; then
    [[ -f "$DCTL_CLI_CONFIG" ]] || err "Configured devcontainer path from CLI flag does not exist: $DCTL_CLI_CONFIG"
    config_path="$(realpath "$DCTL_CLI_CONFIG")"
    log "Using devcontainer config from CLI flag: $config_path" >&2
    printf '%s\n' "$config_path"
    return 0
  fi

  if [[ -v DCTL_CONFIG ]]; then
    [[ -n "$DCTL_CONFIG" ]] || err "DCTL_CONFIG is set but empty"
    [[ -f "$DCTL_CONFIG" ]] || err "Configured devcontainer path from DCTL_CONFIG does not exist: $DCTL_CONFIG"
    config_path="$(realpath "$DCTL_CONFIG")"
    log "Using devcontainer config from environment variable DCTL_CONFIG: $config_path" >&2
    printf '%s\n' "$config_path"
    return 0
  fi

  canonical_name="$(resolve_canonical_project_name)"
  registry_path="$(_registry_lookup_devcontainer "$canonical_name")"
  if [[ -n "$registry_path" ]]; then
    [[ -f "$registry_path" ]] || err "Configured devcontainer path from project registry does not exist for ${canonical_name} in ${DCTL_CONFIG_DIR}/projects.yaml: $registry_path"
    config_path="$(realpath "$registry_path")"
    log "Using devcontainer config from project registry: ${canonical_name} in ${DCTL_CONFIG_DIR}/projects.yaml -> $config_path" >&2
    printf '%s\n' "$config_path"
    return 0
  fi

  local_path="$(workspace_devcontainer_file)"
  if [[ -f "$local_path" ]]; then
    config_path="$(realpath "$local_path")"
    log "Using devcontainer config from local workspace file: $config_path" >&2
    printf '%s\n' "$config_path"
    return 0
  fi

  sibling_path="$(resolve_work_clone_sibling)"
  if [[ -n "$sibling_path" ]]; then
    log "Using devcontainer config from sibling repo: $sibling_path" >&2
    printf '%s\n' "$sibling_path"
    return 0
  fi

  default_path="${DCTL_CONFIG_DIR}/default/devcontainer.json"
  if [[ -f "$default_path" ]]; then
    config_path="$(realpath "$default_path")"
    log "Using devcontainer config from user global default: $config_path" >&2
    printf '%s\n' "$config_path"
    return 0
  fi

  err "No devcontainer config found for $(workspace_path). Run 'dctl init' or pass --config."
}
