# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_DEPLOY_ALL_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_DEPLOY_ALL_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require commands/deploy/_discover.sh
__dctl_require commands/deploy/plan.sh
__dctl_require commands/deploy/apply.sh

cmd_deploy_all() {
  local mode="${1:-normal}"
  local plan=""
  local dev_name image_name plan_output
  while IFS= read -r dev_name; do
    [[ -n $dev_name ]] || continue
    plan_output="$(_collect_deploy_plan devcontainer "$dev_name" "$mode")" || exit $?
    plan+="$plan_output"$'\n'
  done < <(_discover_installed_devcontainers)
  while IFS= read -r image_name; do
    [[ -n $image_name ]] || continue
    plan_output="$(_collect_deploy_plan image "$image_name" "$mode")" || exit $?
    plan+="$plan_output"$'\n'
  done < <(_discover_installed_images)
  _dedupe_plan "$plan"
}
