# shellcheck shell=bash

[[ -n ${_DCTL_LIB_WORKSPACE_GIT_WORKTREE_LOADED:-} ]] && return 0
readonly _DCTL_LIB_WORKSPACE_GIT_WORKTREE_LOADED=1

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

  # Not a linked worktree - git dir and common dir are identical
  [[ $git_dir != "$common_dir" ]] || return 0

  # Mount the shared .git directory at the same host path inside the container
  # so the absolute gitdir reference in the worktree's .git file resolves
  _out=(--mount "type=bind,source=${common_dir},target=${common_dir}")
}
