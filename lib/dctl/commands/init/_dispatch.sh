# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_INIT_DISPATCH_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_INIT_DISPATCH_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require commands/init/do.sh

usage_init() {
  cat <<'EOF'
Usage: dctl init [options]

Register the current project against a deployed devcontainer config and run
the workspace smoke test.

Options:
  --devcontainer <name>                Use a specific deployed devcontainer
  --force                              Rebuild cached merged config and re-register
  --help, -h                           Show this help text

Examples:
  dctl init --devcontainer python
  dctl init --force --devcontainer rust
  dctl init
EOF
}

main_init() {
  cmd_init_do "$@"
}
