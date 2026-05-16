# shellcheck shell=bash
# Workspace (ws) commands for dctl (sourced, not executed directly)

[[ -n ${_DCTL_WS_LOADED:-} ]] && return 0
readonly _DCTL_WS_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require _lib/workspace/git_worktree.sh
__dctl_require _lib/workspace/resolve_config.sh
__dctl_require _lib/term/collect_env.sh
__dctl_require _lib/auth/collect_env.sh

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/common.sh"
# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/auth.sh"
# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/init.sh"

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
  if [[ -n $running_ids ]]; then
    return 0
  fi

  log "No running devcontainer for $(workspace_path); starting one now..."
  cmd_ws_up
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
  local args=("$@")
  if [[ ${#args[@]} -gt 0 && ${args[0]} == "--" ]]; then
    args=("${args[@]:1}")
  fi

  local config_path
  if ! config_path="$(resolve_devcontainer_config)"; then
    return 1
  fi

  # Decide whether to regenerate the merged cache before re-up. Two paths:
  #   (a) The current project has a manifest registered — use it directly.
  #   (b) No registry entry, but the resolved config still lives inside the
  #       cache dir (likely came from --config/DCTL_CONFIG pointing at a
  #       cached file). Recover the manifest name from the parent dir.
  local template_name=""
  local canonical_name registry_manifest
  canonical_name="$(resolve_canonical_project_name)"
  if command -v yq >/dev/null 2>&1; then
    registry_manifest="$(_registry_lookup_devcontainer_manifest "$canonical_name" || true)"
  else
    registry_manifest=""
  fi

  if [[ -n $registry_manifest ]]; then
    template_name="$registry_manifest"
  else
    local cache_root_canonical="$DCTL_DEVCONTAINER_CACHE_DIR"
    if [[ -d $DCTL_DEVCONTAINER_CACHE_DIR ]]; then
      cache_root_canonical="$(realpath "$DCTL_DEVCONTAINER_CACHE_DIR")"
    fi
    if [[ $config_path == "${cache_root_canonical}/"* ]]; then
      template_name="$(basename "$(dirname "$config_path")")"
    fi
  fi

  if [[ -n $template_name ]]; then
    local cache_output config_status
    cache_output="$(generate_cached_devcontainer "$template_name")" || return $?
    config_path="$(head -1 <<<"$cache_output")"
    config_status="$(tail -1 <<<"$cache_output")"
    log "Config cache status: $config_status"
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
  if [[ -z $ids ]]; then
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
  if [[ -z $ids ]]; then
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
