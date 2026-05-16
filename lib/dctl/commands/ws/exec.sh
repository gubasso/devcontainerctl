# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_WS_EXEC_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_WS_EXEC_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require commands/ws/_helpers.sh

cmd_ws_exec() {
  ensure_ws_container_running

  local args=("$@")
  if [[ ${#args[@]} -gt 0 && ${args[0]} == "--" ]]; then
    args=("${args[@]:1}")
  fi
  if [[ ${#args[@]} -eq 0 ]]; then
    args=(bash)
  fi

  devcontainer_exec "${args[@]}"
}
