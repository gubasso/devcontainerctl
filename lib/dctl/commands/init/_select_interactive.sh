# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_INIT_SELECT_INTERACTIVE_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_INIT_SELECT_INTERACTIVE_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require _lib/fzf.sh

_discover_deployed_selectable_devcontainers() {
  local manifests=()
  shopt -s nullglob
  local f name
  for f in "$DCTL_DEVCONTAINER_DIR"/*.yaml; do
    name="$(basename "$f" .yaml)"
    manifests+=("$name")
  done
  shopt -u nullglob
  [[ ${#manifests[@]} -gt 0 ]] && printf '%s\n' "${manifests[@]}"
}

_select_deployed_devcontainer_interactive() {
  local -a available=()
  mapfile -t available < <(_discover_deployed_selectable_devcontainers)

  [[ ${#available[@]} -gt 0 ]] || err "No devcontainers deployed. Run: dctl deploy (or dctl deploy devcontainer <name>)"
  command -v fzf >/dev/null 2>&1 || err "fzf not found. Install fzf or pass --devcontainer <name>."
  [[ -t 0 ]] || err "Interactive init requires a terminal. Pass --devcontainer <name>."

  printf '%s\n' "${available[@]}" | _fzf_pick \
    "Select deployed devcontainer: " \
    "ENTER: confirm, ESC: cancel"
}

_validate_deployed_devcontainer() {
  local template="$1"
  local manifest
  manifest="$(config_compose_manifest_path "$template")"
  [[ -f $manifest ]] || err "Unknown deployed devcontainer: $template (no manifest at $manifest)"
}
