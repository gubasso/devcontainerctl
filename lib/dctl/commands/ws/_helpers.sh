# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_WS_HELPERS_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_WS_HELPERS_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require _lib/workspace/git_worktree.sh
__dctl_require _lib/workspace/resolve_config.sh
__dctl_require _lib/term/collect_env.sh
__dctl_require _lib/auth/collect_env.sh

list_ws_containers() {
  local filter
  filter="$(workspace_label_filter)"
  docker ps -a --filter "$filter" --format '{{.ID}}'
}

list_running_ws_containers() {
  local filter
  filter="$(workspace_label_filter)"
  docker ps --filter "$filter" --format '{{.ID}}'
}

ensure_ws_container_running() {
  require_cmd docker
  require_cmd devcontainer

  local running_ids
  running_ids="$(list_running_ws_containers)"
  if [[ -n $running_ids ]]; then
    return 0
  fi

  log "No running devcontainer for $(workspace_path); starting one now..."
  cmd_ws_up
}

devcontainer_exec() {
  local config_path
  if ! config_path="$(resolve_devcontainer_config)"; then
    return 1
  fi
  local -a term_args auth_args
  collect_term_env term_args
  collect_auth_env auth_args
  devcontainer exec --workspace-folder "$WORKSPACE_FOLDER" --config "$config_path" "${term_args[@]}" "${auth_args[@]}" "$@"
}
