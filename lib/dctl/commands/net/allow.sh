# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_NET_ALLOW_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_NET_ALLOW_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/workspace/canonical_name.sh
__dctl_require _lib/registry/lookup_manifest.sh
__dctl_require commands/net/_compose.sh
__dctl_require commands/net/_user_allowlist.sh
__dctl_require commands/init/_generate_cache.sh

cmd_net_allow() {
  local host="${1:-}"
  [[ -n $host ]] || err "Usage: dctl net allow <host>"
  [[ $# -eq 1 ]] || err "Usage: dctl net allow <host>"

  host="$(_net_normalize_allowlist_entry "$host")"
  _net_allowlist_entry_valid "$host" || err "Invalid allowlist host: $host"

  local leaf_path manifest_name tmp_path
  leaf_path="$(_net_resolve_leaf_config "$WORKSPACE_FOLDER")"
  [[ -n $leaf_path && -f $leaf_path ]] || err "Could not resolve editable devcontainer leaf for $(workspace_path)"

  tmp_path="$(mktemp "${leaf_path}.tmp.XXXXXX")"
  if ! jq --arg host "$host" '
    (.network //= {}) |
    .network.allow = (((.network.allow // []) + [$host]) | unique)
  ' < <(sed '/^[[:space:]]*\/\//d' "$leaf_path") >"$tmp_path"; then
    rm -f "$tmp_path"
    err "Failed to update allowlist in $leaf_path"
  fi
  mv "$tmp_path" "$leaf_path"

  # Regenerate the matching cached config. `_net_resolve_manifest_name`
  # mirrors the override/registry precedence used to pick the leaf, so a
  # caller that pinned `DCTL_CONFIG` to a cached manifest path still
  # refreshes the right cache; an unregistered workspace that edits its
  # own `.devcontainer/devcontainer.json` directly skips this step.
  manifest_name="$(_net_resolve_manifest_name)"
  if [[ -n $manifest_name ]]; then
    generate_cached_devcontainer "$manifest_name" true >/dev/null || return 1
  fi

  cmd_net_show
}
