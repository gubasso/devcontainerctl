# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_IMAGE_LIST_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_IMAGE_LIST_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require commands/image/_helpers.sh

cmd_image_list() {
  if ! ensure_image_dir_exists; then
    return 0
  fi

  discover_image_targets
}
