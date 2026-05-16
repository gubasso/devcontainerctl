# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_WS_REUP_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_WS_REUP_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require _lib/workspace/git_worktree.sh
__dctl_require _lib/workspace/resolve_config.sh
__dctl_require _lib/term/collect_env.sh
__dctl_require _lib/auth/collect_env.sh
__dctl_require _lib/registry/lookup_manifest.sh
__dctl_require commands/ws/_helpers.sh
__dctl_require commands/init/_generate_cache.sh
__dctl_require runtime/common.sh
__dctl_require runtime/krun.sh

cmd_ws_reup() {
  local args=("$@")
  if [[ ${#args[@]} -gt 0 && ${args[0]} == "--" ]]; then
    args=("${args[@]:1}")
  fi

  local config_path
  if ! config_path="$(resolve_devcontainer_config)"; then
    return 1
  fi

  # Decide whether to regenerate the merged cache before re-up. Two paths:
  #   (a) The current project has a manifest registered — use it directly.
  #   (b) No registry entry, but the resolved config still lives inside the
  #       cache dir (likely came from --config/DCTL_CONFIG pointing at a
  #       cached file). Recover the manifest name from the parent dir.
  local template_name=""
  local canonical_name registry_manifest
  canonical_name="$(resolve_canonical_project_name)"
  if command -v yq >/dev/null 2>&1; then
    registry_manifest="$(_registry_lookup_devcontainer_manifest "$canonical_name" || true)"
  else
    registry_manifest=""
  fi

  if [[ -n $registry_manifest ]]; then
    template_name="$registry_manifest"
  else
    local cache_root_canonical="$DCTL_DEVCONTAINER_CACHE_DIR"
    if [[ -d $DCTL_DEVCONTAINER_CACHE_DIR ]]; then
      cache_root_canonical="$(realpath "$DCTL_DEVCONTAINER_CACHE_DIR")"
    fi
    if [[ $config_path == "${cache_root_canonical}/"* ]]; then
      template_name="$(basename "$(dirname "$config_path")")"
    fi
  fi

  if [[ -n $template_name ]]; then
    local cache_output config_status
    cache_output="$(generate_cached_devcontainer "$template_name")" || return $?
    config_path="$(head -1 <<<"$cache_output")"
    config_status="$(tail -1 <<<"$cache_output")"
    log "Config cache status: $config_status"
  fi

  local -a git_wt_mounts=()
  collect_git_worktree_mounts git_wt_mounts
  log "Recreating devcontainer for $(workspace_path)"
  # rt_rm returns 0 when no containers match (handled inside the adapter),
  # so we surface real removal failures instead of masking them.
  rt_rm "$WORKSPACE_FOLDER" >/dev/null
  rt_run "$WORKSPACE_FOLDER" "$config_path" "${git_wt_mounts[@]}" "${args[@]}"
}
