# shellcheck shell=bash
# Shared primitives for dctl modules (sourced, not executed directly)

[[ -n ${_DCTL_COMMON_LOADED:-} ]] && return 0
readonly _DCTL_COMMON_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require _lib/fzf.sh
__dctl_require _lib/workspace/canonical_name.sh
__dctl_require _lib/workspace/label_filter.sh
__dctl_require _lib/workspace/sibling.sh
__dctl_require _lib/workspace/resolve_config.sh
__dctl_require _lib/registry/lookup_manifest.sh
__dctl_require _lib/registry/lookup_discovery.sh
