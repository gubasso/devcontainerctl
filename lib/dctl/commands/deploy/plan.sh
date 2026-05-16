# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_DEPLOY_PLAN_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_DEPLOY_PLAN_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require _lib/registry/validate_manifest.sh
__dctl_require _lib/registry/read_manifest_layers.sh
__dctl_require commands/deploy/_discover.sh
__dctl_require commands/deploy/_dispatch.sh

cmd_deploy_plan() {
  local category="$1"
  shift
  local mode="${1:-normal}"
  shift || true
  local plan=""
  local name plan_output

  for name in "$@"; do
    plan_output="$(_collect_deploy_plan "$category" "$name" "$mode")" || exit $?
    plan+="$plan_output"$'\n'
  done

  _dedupe_plan "$plan"
}
