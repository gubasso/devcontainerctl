# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_WS_DISPATCH_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_WS_DISPATCH_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require commands/ws/_helpers.sh

usage_ws() {
  cat <<'EOF'
Usage: dctl ws <command> [options]

Commands:
  up [-- <runtime args...>]
      Start or attach to the current workspace container.

  reup [-- <runtime args...>]
      Recreate the current workspace container.

  exec [-- <command...>]
      Execute a command in the current workspace container.
      Defaults to: bash

  shell [<command...>]
      Open an interactive shell, or run a command in an interactive login shell.

  run [--] <command...>
      Execute a command via bash -lc inside the workspace container.

  status
      Show container(s) associated with the current workspace.

  down
      Stop and remove container(s) associated with the current workspace.

  help
      Show this help text.

Examples:
  dctl ws up
  dctl ws up -- --env FOO=bar
  dctl ws reup
  dctl ws exec -- id
  dctl ws shell codex
  dctl ws run -- pytest -q

Notes:
  Anything after `--` is forwarded to `podman run`. To rebuild the image
  before `dctl ws reup`, run `dctl image build <image>` (or `dctl image
  build --full-rebuild` to rebuild every managed image from scratch).
EOF
}

main_ws() {
  local command="${1:-help}"

  case "$command" in
    up)
      shift
      __dctl_require commands/ws/up.sh
      cmd_ws_up "$@"
      ;;
    reup)
      shift
      __dctl_require commands/ws/reup.sh
      cmd_ws_reup "$@"
      ;;
    exec)
      shift
      __dctl_require commands/ws/exec.sh
      cmd_ws_exec "$@"
      ;;
    shell)
      shift
      __dctl_require commands/ws/shell.sh
      cmd_ws_shell "$@"
      ;;
    run)
      shift
      __dctl_require commands/ws/run.sh
      cmd_ws_run "$@"
      ;;
    status)
      shift
      __dctl_require commands/ws/status.sh
      cmd_ws_status "$@"
      ;;
    down)
      shift
      __dctl_require commands/ws/down.sh
      cmd_ws_down "$@"
      ;;
    help | -h | --help)
      usage_ws
      ;;
    *)
      err "Unknown ws command: $command"
      ;;
  esac
}
