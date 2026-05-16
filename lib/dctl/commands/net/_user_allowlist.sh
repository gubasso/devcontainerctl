# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_NET_USER_ALLOWLIST_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_NET_USER_ALLOWLIST_LOADED=1

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require _lib/workspace/canonical_name.sh
__dctl_require _lib/workspace/resolve_config.sh
__dctl_require _lib/registry/lookup_manifest.sh

net_user_allowlist() {
  local workspace_folder="${1:-$WORKSPACE_FOLDER}"
  local leaf_path
  leaf_path="$(_net_resolve_leaf_config "$workspace_folder")" || return 0
  [[ -n $leaf_path && -f $leaf_path ]] || return 0
  jq -r '.network.allow // [] | .[]' < <(sed '/^[[:space:]]*\/\//d' "$leaf_path") 2>/dev/null || true
}

_net_resolve_leaf_config() {
  local workspace_folder="${1:-$WORKSPACE_FOLDER}"
  local manifest_name config_path

  manifest_name="${DCTL_NET_MANIFEST_HINT:-}"
  if [[ -n $manifest_name ]]; then
    _net_manifest_leaf_config "$manifest_name"
    return 0
  fi

  # Explicit caller overrides (CLI flag, DCTL_CONFIG env) must beat the
  # project-registry shortcut: a user who pinned a specific devcontainer file
  # expects `dctl net allow/show` to read and mutate that file, not the
  # registered manifest's registry leaf. Resolve the precedence-respecting
  # path first; only fall back to the manifest leaf when no override is in
  # play.
  if [[ -n ${DCTL_CLI_CONFIG:-} || -v DCTL_CONFIG ]]; then
    config_path="$(resolve_devcontainer_config 2>/dev/null || true)"
    if [[ -n $config_path && -f $config_path ]]; then
      if [[ $config_path == "${DCTL_DEVCONTAINER_CACHE_DIR}/"* ]]; then
        manifest_name="$(basename "$(dirname "$config_path")")"
        _net_manifest_leaf_config "$manifest_name"
      else
        printf '%s\n' "$config_path"
      fi
      return 0
    fi
  fi

  manifest_name="$(_registry_lookup_devcontainer_manifest "$(resolve_canonical_project_name)" 2>/dev/null || true)"
  if [[ -n $manifest_name ]]; then
    _net_manifest_leaf_config "$manifest_name"
    return 0
  fi

  config_path="$(resolve_devcontainer_config 2>/dev/null || true)"
  [[ -n $config_path ]] || return 0

  if [[ $config_path == "$workspace_folder/.devcontainer/devcontainer.json" ]]; then
    printf '%s\n' "$config_path"
    return 0
  fi

  if [[ $config_path == "${DCTL_DEVCONTAINER_CACHE_DIR}/"* ]]; then
    manifest_name="$(basename "$(dirname "$config_path")")"
    _net_manifest_leaf_config "$manifest_name"
    return 0
  fi
}

_net_manifest_leaf_config() {
  local manifest_name="$1"
  local manifest_path last_layer

  manifest_path="$(config_compose_manifest_path "$manifest_name")"
  [[ -f $manifest_path ]] || return 0
  last_layer="$(yq eval '.layers[-1]' "$manifest_path" 2>/dev/null || true)"
  [[ -n $last_layer ]] || return 0
  printf '%s/%s/devcontainer.json\n' "$DCTL_DEVCONTAINER_DIR" "$last_layer"
}

# Resolve the manifest name that owns the leaf returned by
# `_net_resolve_leaf_config`. Mirrors the override/registry precedence so
# `cmd_net_allow` can refresh the correct cached config even when an
# explicit `--config` / `DCTL_CONFIG` pinned the cache path of a manifest
# that is not registered for the active project. Returns empty when no
# manifest is in play (direct workspace leaf or no resolvable config).
_net_resolve_manifest_name() {
  local config_path manifest_name

  manifest_name="${DCTL_NET_MANIFEST_HINT:-}"
  if [[ -n $manifest_name ]]; then
    printf '%s\n' "$manifest_name"
    return 0
  fi

  if [[ -n ${DCTL_CLI_CONFIG:-} || -v DCTL_CONFIG ]]; then
    config_path="$(resolve_devcontainer_config 2>/dev/null || true)"
    if [[ -n $config_path && $config_path == "${DCTL_DEVCONTAINER_CACHE_DIR}/"* ]]; then
      printf '%s\n' "$(basename "$(dirname "$config_path")")"
      return 0
    fi
    # Override resolves to a direct file (workspace leaf or sibling/default):
    # there is no owning manifest to regenerate.
    return 0
  fi

  manifest_name="$(_registry_lookup_devcontainer_manifest "$(resolve_canonical_project_name)" 2>/dev/null || true)"
  if [[ -n $manifest_name ]]; then
    printf '%s\n' "$manifest_name"
    return 0
  fi

  config_path="$(resolve_devcontainer_config 2>/dev/null || true)"
  if [[ -n $config_path && $config_path == "${DCTL_DEVCONTAINER_CACHE_DIR}/"* ]]; then
    printf '%s\n' "$(basename "$(dirname "$config_path")")"
    return 0
  fi
}
