# shellcheck shell=bash

[[ -n ${_DCTL_LIB_WORKSPACE_RESOLVE_CONFIG_LOADED:-} ]] && return 0
readonly _DCTL_LIB_WORKSPACE_RESOLVE_CONFIG_LOADED=1

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require _lib/workspace/canonical_name.sh
__dctl_require _lib/workspace/sibling.sh
__dctl_require _lib/registry/lookup_manifest.sh

resolve_devcontainer_config() {
  require_cmd realpath

  local config_path
  local canonical_name
  local registry_manifest
  local registry_path
  local local_path
  local sibling_path
  local default_path

  if [[ -n ${DCTL_CLI_CONFIG:-} ]]; then
    [[ -f $DCTL_CLI_CONFIG ]] || err "Configured devcontainer path from CLI flag does not exist: $DCTL_CLI_CONFIG"
    config_path="$(realpath "$DCTL_CLI_CONFIG")"
    log "Using devcontainer config from CLI flag: $config_path" >&2
    printf '%s\n' "$config_path"
    return 0
  fi

  if [[ -v DCTL_CONFIG ]]; then
    [[ -n $DCTL_CONFIG ]] || err "DCTL_CONFIG is set but empty"
    [[ -f $DCTL_CONFIG ]] || err "Configured devcontainer path from DCTL_CONFIG does not exist: $DCTL_CONFIG"
    config_path="$(realpath "$DCTL_CONFIG")"
    log "Using devcontainer config from environment variable DCTL_CONFIG: $config_path" >&2
    printf '%s\n' "$config_path"
    return 0
  fi

  canonical_name="$(resolve_canonical_project_name)"
  registry_manifest="$(_registry_lookup_devcontainer_manifest "$canonical_name")"
  if [[ -n $registry_manifest ]]; then
    registry_path="$(devcontainer_cache_path_for_manifest "$registry_manifest")"
    [[ -f $registry_path ]] || err "Registry manifest '${registry_manifest}' for project '${canonical_name}' has no generated cache at $registry_path. Run: dctl init --devcontainer ${registry_manifest}"
    config_path="$(realpath "$registry_path")"
    log "Using devcontainer config from project registry: ${canonical_name} (manifest: ${registry_manifest}) -> $config_path" >&2
    printf '%s\n' "$config_path"
    return 0
  fi

  local_path="$(workspace_devcontainer_file)"
  if [[ -f $local_path ]]; then
    config_path="$(realpath "$local_path")"
    log "Using devcontainer config from local workspace file: $config_path" >&2
    printf '%s\n' "$config_path"
    return 0
  fi

  sibling_path="$(resolve_work_clone_sibling)"
  if [[ -n $sibling_path ]]; then
    log "Using devcontainer config from sibling repo: $sibling_path" >&2
    printf '%s\n' "$sibling_path"
    return 0
  fi

  default_path="${DCTL_CONFIG_DIR}/default/devcontainer.json"
  if [[ -f $default_path ]]; then
    config_path="$(realpath "$default_path")"
    log "Using devcontainer config from user global default: $config_path" >&2
    printf '%s\n' "$config_path"
    return 0
  fi

  err "No devcontainer config found for $(workspace_path). Run 'dctl init' or pass --config."
}
