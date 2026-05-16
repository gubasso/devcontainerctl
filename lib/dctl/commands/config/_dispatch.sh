# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_CONFIG_DISPATCH_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_CONFIG_DISPATCH_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh

usage_config() {
  cat <<'EOF'
Usage: dctl config <command>

Commands:
  help    Show this help text

Project registry: ~/.config/dctl/projects.yaml
EOF
}

cmd_config() {
  local command="${1:-help}"
  case "$command" in
    help | -h | --help)
      usage_config
      ;;
    *)
      err "Unknown config command: $command"
      ;;
  esac
}

main_config() {
  cmd_config "$@"
}
