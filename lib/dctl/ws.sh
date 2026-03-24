# shellcheck shell=bash
# Workspace (ws) commands for dctl (sourced, not executed directly)

[[ -n "${_DCTL_WS_LOADED:-}" ]] && return 0
readonly _DCTL_WS_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/common.sh"
# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/auth.sh"

require_dotfiles_dir() {
  DOTFILES="${DOTFILES:-${HOME}/.dotfiles}"
  [[ -d "$DOTFILES" ]] || err "Dotfiles not found at ${DOTFILES} — set DOTFILES= or ensure ~/.dotfiles exists"
  export DOTFILES
}

usage_ws() {
  cat <<'EOF'
Usage: dctl ws <command> [options]

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
  dctl ws up
  dctl ws reup -- --build-no-cache
  dctl ws exec -- id
  dctl ws shell codex
  dctl ws run -- pytest -q
EOF
}

list_ws_containers() {
  local filter
  filter="$(workspace_label_filter)"
  docker ps -a --filter "$filter" --format '{{.ID}}'
}

list_running_ws_containers() {
  local filter
  filter="$(workspace_label_filter)"
  docker ps --filter "$filter" --format '{{.ID}}'
}

ensure_ws_container_running() {
  require_cmd docker
  require_cmd devcontainer

  local running_ids
  running_ids="$(list_running_ws_containers)"
  if [[ -n "$running_ids" ]]; then
    return 0
  fi

  log "No running devcontainer for $(workspace_path); starting one now..."
  cmd_ws_up
}

# If the workspace is a git linked worktree, populate mount args for the
# shared .git directory so git operations work inside the container.
# Usage: local -a git_wt_mounts=(); collect_git_worktree_mounts git_wt_mounts
collect_git_worktree_mounts() {
  local -n _out="$1"
  _out=()

  command -v git &>/dev/null || return 0

  local git_dir common_dir
  git_dir="$(git -C "$WORKSPACE_FOLDER" rev-parse --git-dir 2>/dev/null)" || return 0
  common_dir="$(git -C "$WORKSPACE_FOLDER" rev-parse --git-common-dir 2>/dev/null)" || return 0

  # Resolve to absolute paths
  git_dir="$(cd -- "$WORKSPACE_FOLDER" && cd -- "$git_dir" && pwd -P)"
  common_dir="$(cd -- "$WORKSPACE_FOLDER" && cd -- "$common_dir" && pwd -P)"

  # Not a linked worktree — git dir and common dir are identical
  [[ "$git_dir" != "$common_dir" ]] || return 0

  # Mount the shared .git directory at the same host path inside the container
  # so the absolute gitdir reference in the worktree's .git file resolves
  _out=(--mount "type=bind,source=${common_dir},target=${common_dir}")
}

collect_term_env() {
  local -n out="$1"
  out=()

  local var_name
  for var_name in TERM COLORTERM TERM_PROGRAM TERM_PROGRAM_VERSION KITTY_WINDOW_ID KITTY_LISTEN_ON; do
    if [[ -n "${!var_name:-}" ]]; then
      out+=(--remote-env "${var_name}=${!var_name}")
    fi
  done
}

devcontainer_exec() {
  local config_path
  if ! config_path="$(resolve_devcontainer_config)"; then
    return 1
  fi
  local -a term_args auth_args
  collect_term_env term_args
  collect_auth_env auth_args
  devcontainer exec --workspace-folder "$WORKSPACE_FOLDER" --config "$config_path" "${term_args[@]}" "${auth_args[@]}" "$@"
}

cmd_ws_up() {
  require_cmd devcontainer
  require_dotfiles_dir
  local args=("$@")
  if [[ ${#args[@]} -gt 0 && ${args[0]} == "--" ]]; then
    args=("${args[@]:1}")
  fi

  local config_path
  if ! config_path="$(resolve_devcontainer_config)"; then
    return 1
  fi

  local -a git_wt_mounts=()
  collect_git_worktree_mounts git_wt_mounts
  log "Starting devcontainer for $(workspace_path)"
  devcontainer up --workspace-folder "$WORKSPACE_FOLDER" --config "$config_path" "${git_wt_mounts[@]}" "${args[@]}"
}

cmd_ws_reup() {
  require_cmd devcontainer
  require_dotfiles_dir
  local args=("$@")
  if [[ ${#args[@]} -gt 0 && ${args[0]} == "--" ]]; then
    args=("${args[@]:1}")
  fi

  local config_path
  if ! config_path="$(resolve_devcontainer_config)"; then
    return 1
  fi

  local -a git_wt_mounts=()
  collect_git_worktree_mounts git_wt_mounts
  log "Recreating devcontainer for $(workspace_path)"
  devcontainer up --workspace-folder "$WORKSPACE_FOLDER" --config "$config_path" --remove-existing-container "${git_wt_mounts[@]}" "${args[@]}"
}

cmd_ws_exec() {
  ensure_ws_container_running

  local args=("$@")
  if [[ ${#args[@]} -gt 0 && ${args[0]} == "--" ]]; then
    args=("${args[@]:1}")
  fi
  if [[ ${#args[@]} -eq 0 ]]; then
    args=(bash)
  fi

  devcontainer_exec "${args[@]}"
}

cmd_ws_shell() {
  ensure_ws_container_running

  if [[ $# -gt 0 ]]; then
    devcontainer_exec bash -lic "$*"
  else
    devcontainer_exec bash
  fi
}

cmd_ws_run() {
  ensure_ws_container_running

  if [[ ${1:-} == "--" ]]; then
    shift
  fi
  [[ $# -gt 0 ]] || err "run requires a command. Example: dctl ws run -- claude-session"

  devcontainer_exec bash -lc "$*"
}

cmd_ws_status() {
  require_cmd docker

  local filter
  filter="$(workspace_label_filter)"

  local ids
  ids="$(list_ws_containers)"
  if [[ -z "$ids" ]]; then
    warn "No devcontainer found for workspace: $(workspace_path)"
    return 0
  fi

  docker ps -a \
    --filter "$filter" \
    --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Image}}\t{{.RunningFor}}'
}

cmd_ws_down() {
  require_cmd docker

  local filter
  filter="$(workspace_label_filter)"

  local ids
  ids="$(list_ws_containers)"
  if [[ -z "$ids" ]]; then
    warn "No devcontainer to remove for workspace: $(workspace_path)"
    return 0
  fi

  log "Removing devcontainer(s) for $(workspace_path)"
  docker ps -aq --filter "$filter" | xargs -r docker rm -f
}

main_ws() {
  local command="${1:-help}"

  case "$command" in
    up)
      shift
      cmd_ws_up "$@"
      ;;
    reup)
      shift
      cmd_ws_reup "$@"
      ;;
    exec)
      shift
      cmd_ws_exec "$@"
      ;;
    shell)
      shift
      cmd_ws_shell "$@"
      ;;
    run)
      shift
      cmd_ws_run "$@"
      ;;
    status)
      shift
      cmd_ws_status "$@"
      ;;
    down)
      shift
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
