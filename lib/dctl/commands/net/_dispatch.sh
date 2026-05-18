# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_NET_DISPATCH_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_NET_DISPATCH_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh

usage_net() {
  cat <<'EOF'
Usage: dctl net <command> [options]

Commands:
  allow <host>
      Append a host or CIDR to the editable leaf devcontainer allowlist and
      regenerate the manifest cache when applicable.

  show
      Print the effective allowlist with origin annotations.

  help
      Show this help text.
EOF
}

main_net() {
  local command="${1:-help}"

  case "$command" in
    help | -h | --help)
      usage_net
      return 0
      ;;
  esac

  require_cmds jq

  case "$command" in
    allow)
      shift
      __dctl_require commands/net/allow.sh
      cmd_net_allow "$@"
      ;;
    show)
      shift
      __dctl_require commands/net/show.sh
      cmd_net_show "$@"
      ;;
    *)
      err "Unknown net command: $command"
      ;;
  esac
}
