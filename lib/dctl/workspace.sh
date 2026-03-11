# shellcheck shell=bash
# Workspace commands for dctl (sourced, not executed directly)

[[ -n "${_DCTL_WORKSPACE_LOADED:-}" ]] && return 0
readonly _DCTL_WORKSPACE_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/common.sh"

usage_workspace() {
  cat <<'EOF'
Usage: dctl workspace <command> [options]

Commands:
  up [-- <devcontainer up args...>]
      Start or attach to the current workspace's devcontainer.

  reup [-- <devcontainer up args...>]
      Recreate the current workspace's devcontainer.

  exec [-- <command...>]
      Execute a command in the current workspace's devcontainer.
      Defaults to: bash

  shell [<command...>]
      Open an interactive shell, or run a command in an interactive login shell.

  run [--] <command...>
      Execute a command via bash -lc inside the devcontainer.

  status
      Show devcontainer(s) associated with the current workspace.

  down
      Stop and remove devcontainer(s) associated with the current workspace.

  help
      Show this help text.

Examples:
  dctl workspace up
  dctl workspace reup -- --build-no-cache
  dctl workspace exec -- id
  dctl workspace shell codex
  dctl workspace run -- pytest -q
EOF
}

list_workspace_containers() {
  local filter
  filter="$(workspace_label_filter)"
  docker ps -a --filter "$filter" --format '{{.ID}}'
}

list_running_workspace_containers() {
  local filter
  filter="$(workspace_label_filter)"
  docker ps --filter "$filter" --format '{{.ID}}'
}

ensure_workspace_container_running() {
  require_cmd docker
  require_cmd devcontainer

  local running_ids
  running_ids="$(list_running_workspace_containers)"
  if [[ -n "$running_ids" ]]; then
    return 0
  fi

  log "No running devcontainer for $(workspace_path); starting one now..."
  cmd_workspace_up
}

collect_term_env() {
  local -n out="$1"
  out=()

  local var_name
  for var_name in TERM COLORTERM TERM_PROGRAM TERM_PROGRAM_VERSION; do
    if [[ -n "${!var_name:-}" ]]; then
      out+=(--remote-env "${var_name}=${!var_name}")
    fi
  done
}

devcontainer_exec() {
  local -a term_args
  collect_term_env term_args
  devcontainer exec --workspace-folder "$WORKSPACE_FOLDER" "${term_args[@]}" "$@"
}

cmd_workspace_up() {
  require_cmd devcontainer
  local args=("$@")
  if [[ ${#args[@]} -gt 0 && ${args[0]} == "--" ]]; then
    args=("${args[@]:1}")
  fi

  log "Starting devcontainer for $(workspace_path)"
  devcontainer up --workspace-folder "$WORKSPACE_FOLDER" "${args[@]}"
}

cmd_workspace_reup() {
  require_cmd devcontainer
  local args=("$@")
  if [[ ${#args[@]} -gt 0 && ${args[0]} == "--" ]]; then
    args=("${args[@]:1}")
  fi

  log "Recreating devcontainer for $(workspace_path)"
  devcontainer up --workspace-folder "$WORKSPACE_FOLDER" --remove-existing-container "${args[@]}"
}

cmd_workspace_exec() {
  ensure_workspace_container_running

  local args=("$@")
  if [[ ${#args[@]} -gt 0 && ${args[0]} == "--" ]]; then
    args=("${args[@]:1}")
  fi
  if [[ ${#args[@]} -eq 0 ]]; then
    args=(bash)
  fi

  devcontainer_exec "${args[@]}"
}

cmd_workspace_shell() {
  ensure_workspace_container_running

  if [[ $# -gt 0 ]]; then
    devcontainer_exec bash -lic "$*"
  else
    devcontainer_exec bash
  fi
}

cmd_workspace_run() {
  ensure_workspace_container_running

  if [[ ${1:-} == "--" ]]; then
    shift
  fi
  [[ $# -gt 0 ]] || err "run requires a command. Example: dctl workspace run -- claude-session"

  devcontainer_exec bash -lc "$*"
}

cmd_workspace_status() {
  require_cmd docker

  local filter
  filter="$(workspace_label_filter)"

  local ids
  ids="$(list_workspace_containers)"
  if [[ -z "$ids" ]]; then
    warn "No devcontainer found for workspace: $(workspace_path)"
    return 0
  fi

  docker ps -a \
    --filter "$filter" \
    --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Image}}\t{{.RunningFor}}'
}

cmd_workspace_down() {
  require_cmd docker

  local filter
  filter="$(workspace_label_filter)"

  local ids
  ids="$(list_workspace_containers)"
  if [[ -z "$ids" ]]; then
    warn "No devcontainer to remove for workspace: $(workspace_path)"
    return 0
  fi

  log "Removing devcontainer(s) for $(workspace_path)"
  docker ps -aq --filter "$filter" | xargs -r docker rm -f
}

main_workspace() {
  local command="${1:-help}"

  case "$command" in
    up)
      shift
      cmd_workspace_up "$@"
      ;;
    reup)
      shift
      cmd_workspace_reup "$@"
      ;;
    exec)
      shift
      cmd_workspace_exec "$@"
      ;;
    shell)
      shift
      cmd_workspace_shell "$@"
      ;;
    run)
      shift
      cmd_workspace_run "$@"
      ;;
    status)
      shift
      cmd_workspace_status "$@"
      ;;
    down)
      shift
      cmd_workspace_down "$@"
      ;;
    help | -h | --help)
      usage_workspace
      ;;
    *)
      err "Unknown workspace command: $command"
      ;;
  esac
}
