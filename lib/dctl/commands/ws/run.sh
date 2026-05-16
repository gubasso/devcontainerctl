# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_WS_RUN_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_WS_RUN_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require _lib/term/collect_env.sh
__dctl_require commands/ws/_helpers.sh
__dctl_require runtime/common.sh
__dctl_require runtime/krun.sh

cmd_ws_run() {
  ensure_ws_container_running

  if [[ ${1:-} == "--" ]]; then
    shift
  fi
  [[ $# -gt 0 ]] || err "run requires a command. Example: dctl ws run -- claude-session"

  devcontainer_exec -- bash -lc "$*"
}
