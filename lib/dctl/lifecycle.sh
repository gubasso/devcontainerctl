# shellcheck shell=bash
# Minimal devcontainer.json lifecycle interpreter (sourced, not executed directly)
#
# Accepted keys:
#   - remoteUser
#   - workspaceFolder
#   - workspaceMount
#   - postCreateCommand
#   - postStartCommand
#
# Everything else in the Microsoft devcontainer schema is intentionally ignored
# by dctl at this layer (features, customizations, forwardPorts, editor metadata,
# and related IDE-only settings).

[[ -n ${_DCTL_LIFECYCLE_LOADED:-} ]] && return 0
readonly _DCTL_LIFECYCLE_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/common.sh"

_lifecycle_strip_jsonc_comments() {
  sed '/^[[:space:]]*\/\//d' "$1"
}

_lifecycle_resolve_config() {
  local ctr="$1"
  local workspace_folder config_path

  workspace_folder="$(podman inspect --format '{{ index .Config.Labels "devcontainer.local_folder" }}' "$ctr" 2>/dev/null || true)"
  [[ -n $workspace_folder ]] || err "Container '${ctr}' is missing the devcontainer.local_folder label"

  config_path="$(
    WORKSPACE_FOLDER="$workspace_folder" DCTL_LIB_DIR="$DCTL_LIB_DIR" bash -lc '
      set -euo pipefail
      source "$DCTL_LIB_DIR/common.sh"
      resolve_devcontainer_config
    '
  )" || return 1

  _lifecycle_strip_jsonc_comments "$config_path"
}

# _lifecycle_config_for_ctr <ctr> [<config_json>]
#
# If a caller (typically `_krun_rt_run`) already has the resolved
# devcontainer.json text, it should pass it as the optional second argument so
# the lifecycle stage acts on the same config the container was launched from.
# Otherwise we fall back to re-resolving from the workspace label, which can
# differ when DCTL_CLI_CONFIG / DCTL_CONFIG / sibling-repo precedence kicks in.
_lifecycle_config_for_ctr() {
  local ctr="$1"
  local config_json="${2:-}"

  if [[ -n $config_json ]]; then
    printf '%s' "$config_json"
  else
    _lifecycle_resolve_config "$ctr"
  fi
}

_lifecycle_exec() {
  local ctr="$1"
  local config_json="$2"
  shift 2

  local remote_user workspace_folder
  local -a cmd

  remote_user="$(jq -r '.remoteUser // empty' <<<"$config_json")"
  workspace_folder="$(jq -r '.workspaceFolder // empty' <<<"$config_json")"

  cmd=(podman exec)
  if [[ -n $remote_user ]]; then
    cmd+=(--user "$remote_user")
  fi
  if [[ -n $workspace_folder ]]; then
    cmd+=(--workdir "$workspace_folder")
  fi
  cmd+=("$ctr" "$@")

  "${cmd[@]}"
}

_lifecycle_run_command() {
  local ctr="$1"
  local config_json="$2"
  local jq_expr="$3"
  local value_type key shell_cmd
  local -a argv

  value_type="$(jq -r "${jq_expr} | if . == null then \"null\" else type end" <<<"$config_json")"
  case "$value_type" in
    null)
      return 0
      ;;
    string)
      shell_cmd="$(jq -r "$jq_expr" <<<"$config_json")"
      _lifecycle_exec "$ctr" "$config_json" sh -c "$shell_cmd"
      ;;
    array)
      argv=()
      while IFS= read -r key; do
        argv+=("$key")
      done < <(jq -r "${jq_expr}[]" <<<"$config_json")
      _lifecycle_exec "$ctr" "$config_json" "${argv[@]}"
      ;;
    object)
      while IFS= read -r key; do
        _lifecycle_run_command "$ctr" "$config_json" "${jq_expr}[\"${key}\"]" || return 1
      done < <(jq -r "${jq_expr} | keys_unsorted[]" <<<"$config_json")
      ;;
    *)
      err "Unsupported lifecycle command type '${value_type}'"
      ;;
  esac
}

run_postcreate() {
  local ctr="$1"
  local config_json

  config_json="$(_lifecycle_config_for_ctr "$ctr" "${2:-}")" || return 1
  _lifecycle_run_command "$ctr" "$config_json" '.postCreateCommand'
}

run_poststart() {
  local ctr="$1"
  local config_json

  config_json="$(_lifecycle_config_for_ctr "$ctr" "${2:-}")" || return 1
  _lifecycle_run_command "$ctr" "$config_json" '.postStartCommand'
}
