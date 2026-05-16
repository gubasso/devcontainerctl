# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_WS_UP_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_WS_UP_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require _lib/workspace/git_worktree.sh
__dctl_require _lib/workspace/resolve_config.sh
__dctl_require _lib/term/collect_env.sh
__dctl_require _lib/auth/collect_env.sh
__dctl_require commands/ws/_helpers.sh

cmd_ws_up() {
  require_cmd devcontainer
  local args=("$@")
  if [[ ${#args[@]} -gt 0 && ${args[0]} == "--" ]]; then
    args=("${args[@]:1}")
  fi

  local config_path
  if ! config_path="$(resolve_devcontainer_config)"; then
    return 1
  fi

  local -a git_wt_mounts=()
  collect_git_worktree_mounts git_wt_mounts
  log "Starting devcontainer for $(workspace_path)"
  devcontainer up --workspace-folder "$WORKSPACE_FOLDER" --config "$config_path" "${git_wt_mounts[@]}" "${args[@]}"
}
