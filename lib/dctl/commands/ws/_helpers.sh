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
__dctl_require runtime/common.sh
__dctl_require runtime/krun.sh

list_ws_containers() {
  rt_ps --quiet "$WORKSPACE_FOLDER"
}

list_running_ws_containers() {
  rt_ps --quiet --running "$WORKSPACE_FOLDER"
}

ensure_ws_container_running() {
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
  local -a term_args auth_args exec_env_args
  collect_term_env term_args
  collect_auth_env auth_args

  exec_env_args=()
  _append_rt_exec_env_flags exec_env_args "${term_args[@]}" "${auth_args[@]}"

  rt_exec "$WORKSPACE_FOLDER" "$config_path" "${exec_env_args[@]}" "$@"
}

_append_rt_exec_env_flags() {
  local -n _out="$1"
  shift

  local flag value
  while [[ $# -gt 0 ]]; do
    flag="$1"
    shift
    [[ $# -gt 0 ]] || err "env flag helper received an incomplete flag pair"
    value="$1"
    shift

    case "$flag" in
      --remote-env | --env)
        _out+=(--env "$value")
        ;;
      *)
        err "Unsupported exec env flag '${flag}'"
        ;;
    esac
  done
}
