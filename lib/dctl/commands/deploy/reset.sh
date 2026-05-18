# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_DEPLOY_RESET_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_DEPLOY_RESET_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require commands/deploy/_dispatch.sh

cmd_deploy_reset() {
  local plan="$1"
  _apply_deploy_plan "$plan"
}
