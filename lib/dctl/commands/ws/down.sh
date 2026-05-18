# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_WS_DOWN_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_WS_DOWN_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require _lib/workspace/session_hash.sh
__dctl_require commands/ws/_helpers.sh
__dctl_require runtime/common.sh
__dctl_require runtime/krun.sh

cmd_ws_down() {
  local session_dir ids rc=0
  session_dir="$(workspace_session_dir)" || session_dir=""
  ids="$(rt_ps --quiet "$WORKSPACE_FOLDER")"
  if [[ -z $ids ]]; then
    warn "No devcontainer to remove for workspace: $(workspace_path)"
  else
    log "Removing devcontainer(s) for $(workspace_path)"
    rt_rm "$WORKSPACE_FOLDER" || rc=$?
  fi

  if [[ $rc -eq 0 && -n $session_dir && -d $session_dir ]]; then
    rm -rf -- "$session_dir"
  fi

  return "$rc"
}
