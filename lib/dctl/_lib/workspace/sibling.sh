# shellcheck shell=bash

[[ -n ${_DCTL_LIB_WORKSPACE_SIBLING_LOADED:-} ]] && return 0
readonly _DCTL_LIB_WORKSPACE_SIBLING_LOADED=1

__dctl_require _lib/log.sh
__dctl_require _lib/workspace/canonical_name.sh
__dctl_require _lib/registry/lookup_discovery.sh

resolve_work_clone_sibling() {
  require_cmd realpath

  local canonical_name
  canonical_name="$(resolve_canonical_project_name)"

  local sibling_discovery
  sibling_discovery="$(_registry_lookup_sibling_discovery "$canonical_name")"
  [[ $sibling_discovery == "true" ]] || return 0

  local workspace_basename
  workspace_basename="$(basename "$WORKSPACE_FOLDER")"
  [[ $workspace_basename == *.* ]] || return 0

  local main_repo_name
  main_repo_name="${workspace_basename%%.*}"

  local parent_dir
  parent_dir="$(dirname "$WORKSPACE_FOLDER")"

  local candidate_path
  candidate_path="${parent_dir}/${main_repo_name}"
  [[ -d $candidate_path ]] || return 0

  candidate_path="$(realpath "$candidate_path")"
  [[ $candidate_path != "$WORKSPACE_FOLDER" ]] || return 0
  [[ -d "$candidate_path/.git" ]] || return 0

  local candidate_config
  candidate_config="${candidate_path}/.devcontainer/devcontainer.json"
  [[ -f $candidate_config ]] || return 0

  realpath "$candidate_config"
}
