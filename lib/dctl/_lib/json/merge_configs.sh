# shellcheck shell=bash

[[ -n ${_DCTL_LIB_JSON_MERGE_CONFIGS_LOADED:-} ]] && return 0
readonly _DCTL_LIB_JSON_MERGE_CONFIGS_LOADED=1

__dctl_require _lib/json/strip_comments.sh
__dctl_require _lib/json/validate_layer.sh
__dctl_require _lib/json/merge_runargs.sh

merge_two_configs() {
  local base_path="$1"
  local template_path="$2"

  local base_json tmpl_json jq_err runargs_json

  base_json="$(_strip_jsonc_comments "$base_path")" || return 1
  tmpl_json="$(_strip_jsonc_comments "$template_path")" || return 1

  if ! jq_err="$(jq empty <<<"$base_json" 2>&1)"; then
    printf 'JSON syntax error in %s:\n  %s\n' "$base_path" "$jq_err" >&2
    return 1
  fi
  if ! jq_err="$(jq empty <<<"$tmpl_json" 2>&1)"; then
    printf 'JSON syntax error in %s:\n  %s\n' "$template_path" "$jq_err" >&2
    return 1
  fi

  _validate_devcontainer_layer "$base_path" "$base_json" || return 1
  _validate_devcontainer_layer "$template_path" "$tmpl_json" || return 1

  runargs_json="$(_merge_runargs_json "$base_json" "$tmpl_json")" || return 1

  jq -n \
    --argjson base "$base_json" \
    --argjson tmpl "$tmpl_json" \
    --argjson runargs "$runargs_json" '
      $base as $base |
      $tmpl as $tmpl |
      ($base * $tmpl) |
      .mounts = (($base.mounts // []) + ($tmpl.mounts // [])) |
      .postCreateCommand =
        if (($base.postCreateCommand // null) | type) == "object"
          and (($tmpl.postCreateCommand // null) | type) == "object"
        then (($base.postCreateCommand // {}) * ($tmpl.postCreateCommand // {}))
        else ($tmpl.postCreateCommand // $base.postCreateCommand)
        end |
      .containerEnv = (($base.containerEnv // {}) * ($tmpl.containerEnv // {})) |
      .remoteEnv = (($base.remoteEnv // {}) * ($tmpl.remoteEnv // {})) |
      .runArgs = $runargs |
      if $tmpl.workspaceMount != null then .workspaceMount = $tmpl.workspaceMount else . end |
      if $tmpl.workspaceFolder != null then .workspaceFolder = $tmpl.workspaceFolder else . end
    '
}
