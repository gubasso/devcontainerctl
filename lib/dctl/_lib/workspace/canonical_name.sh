# shellcheck shell=bash

[[ -n ${_DCTL_LIB_WORKSPACE_CANONICAL_NAME_LOADED:-} ]] && return 0
readonly _DCTL_LIB_WORKSPACE_CANONICAL_NAME_LOADED=1

resolve_canonical_project_name() {
  local remote_url=""
  local remote_path=""
  local workspace_basename
  local canonical_name

  if command -v git >/dev/null 2>&1; then
    remote_url="$(git -C "$WORKSPACE_FOLDER" remote get-url origin 2>/dev/null || true)"
  fi

  if [[ -n $remote_url ]]; then
    if [[ $remote_url == *://* ]]; then
      remote_path="${remote_url#*://}"
      remote_path="${remote_path#*/}"
    elif [[ $remote_url == *:* ]]; then
      remote_path="${remote_url#*:}"
    else
      remote_path="$remote_url"
    fi

    remote_path="${remote_path%.git}"
    remote_path="${remote_path#/}"
    printf '%s\n' "${remote_path//\//-}"
    return 0
  fi

  workspace_basename="$(basename "$WORKSPACE_FOLDER")"
  canonical_name="$workspace_basename"
  if [[ $workspace_basename == *.* ]]; then
    canonical_name="${workspace_basename%%.*}"
  fi

  printf '%s\n' "$canonical_name"
}
