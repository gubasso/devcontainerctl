# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_NET_SHOW_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_NET_SHOW_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require commands/net/_compose.sh

cmd_net_show() {
  local host origin
  while IFS=$'\t' read -r host origin; do
    [[ -n $host ]] || continue
    printf '%s\t%s\n' "$origin" "$host"
  done < <(net_compose_allowlist_annotated "$WORKSPACE_FOLDER")
}
