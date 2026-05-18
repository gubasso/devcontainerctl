# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_TEST_DISPATCH_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_TEST_DISPATCH_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require commands/test/run.sh

usage_test() {
  cat <<'EOF'
Usage: dctl test [options]

Validate the current workspace devcontainer setup with a smoke test.

Options:
  --help, -h    Show this help text

Examples:
  dctl test
EOF
}

main_test() {
  warn "'dctl test' will be rewired to podman in Phase 2; use 'dctl doctor' to verify host setup."
  cmd_test_run "$@"
}
