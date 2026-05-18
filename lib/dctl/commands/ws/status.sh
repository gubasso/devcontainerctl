# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_WS_STATUS_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_WS_STATUS_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require commands/ws/_helpers.sh
__dctl_require runtime/common.sh
__dctl_require runtime/krun.sh

cmd_ws_status() {
  local ids
  ids="$(rt_ps --quiet "$WORKSPACE_FOLDER")"
  if [[ -z $ids ]]; then
    warn "No devcontainer found for workspace: $(workspace_path)"
    return 0
  fi

  rt_ps --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Image}}\t{{.RunningFor}}' "$WORKSPACE_FOLDER"
}
