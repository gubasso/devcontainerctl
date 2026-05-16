# shellcheck shell=bash
# Auth token extraction for dctl (sourced, not executed directly)

[[ -n ${_DCTL_AUTH_LOADED:-} ]] && return 0
readonly _DCTL_AUTH_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/auth/gh_token.sh
__dctl_require _lib/auth/glab_token.sh
__dctl_require _lib/auth/collect_env.sh
