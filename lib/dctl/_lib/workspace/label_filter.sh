# shellcheck shell=bash

[[ -n ${_DCTL_LIB_WORKSPACE_LABEL_FILTER_LOADED:-} ]] && return 0
readonly _DCTL_LIB_WORKSPACE_LABEL_FILTER_LOADED=1

__dctl_require _lib/paths.sh

workspace_label_filter() {
  printf 'label=devcontainer.local_folder=%s' "$(workspace_path)"
}
