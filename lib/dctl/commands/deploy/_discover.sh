# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_DEPLOY_DISCOVER_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_DEPLOY_DISCOVER_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh

_discover_installed_devcontainers() {
  local manifests=()
  shopt -s nullglob
  local f name
  for f in "$DEVCONTAINERS_DIR"/*.yaml; do
    name="$(basename "$f" .yaml)"
    manifests+=("$name")
  done
  shopt -u nullglob
  [[ ${#manifests[@]} -gt 0 ]] && printf '%s\n' "${manifests[@]}"
}

_discover_deployed_devcontainers() {
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

_discover_installed_images() {
  local targets=()
  shopt -s nullglob
  local dir name
  for dir in "$IMAGES_DIR"/*/; do
    [[ -f "${dir}Dockerfile" ]] || continue
    name="$(basename "$dir")"
    targets+=("$name")
  done
  shopt -u nullglob
  [[ ${#targets[@]} -gt 0 ]] && printf '%s\n' "${targets[@]}"
}

_discover_deployed_images() {
  local targets=()
  shopt -s nullglob
  local dir name
  for dir in "$DCTL_IMAGES_DIR"/*/; do
    [[ -f "${dir}Dockerfile" ]] || continue
    name="$(basename "$dir")"
    targets+=("$name")
  done
  shopt -u nullglob
  [[ ${#targets[@]} -gt 0 ]] && printf '%s\n' "${targets[@]}"
}

_discover_installed_selectable_devcontainers() {
  _discover_installed_devcontainers
}

_discover_deployed_selectable_devcontainers() {
  _discover_deployed_devcontainers
}

_category_installed_root() {
  case "$1" in
    devcontainer) printf '%s\n' "$DEVCONTAINERS_DIR" ;;
    image) printf '%s\n' "$IMAGES_DIR" ;;
    *) err "Unknown deploy category: $1" ;;
  esac
}

_category_deployed_root() {
  case "$1" in
    devcontainer) printf '%s\n' "$DCTL_DEVCONTAINER_DIR" ;;
    image) printf '%s\n' "$DCTL_IMAGES_DIR" ;;
    *) err "Unknown deploy category: $1" ;;
  esac
}

_preview_file_for_category() {
  case "$1" in
    devcontainer) printf 'devcontainer.json\n' ;;
    image) printf 'Dockerfile\n' ;;
    *) err "Unknown deploy category: $1" ;;
  esac
}

_collect_dir_plan_entries() {
  local category="$1"
  local name="$2"
  local mode="$3"
  local internal="${4:-false}"

  local src_root dest_root src_dir dest_dir
  src_root="$(_category_installed_root "$category")"
  dest_root="$(_category_deployed_root "$category")"
  src_dir="${src_root}/${name}"
  dest_dir="${dest_root}/${name}"

  [[ -d $src_dir ]] || return 0

  local source rel dest action
  while IFS= read -r source; do
    [[ -n $source ]] || continue
    rel="${source#"${src_dir}"/}"
    dest="${dest_dir}/${rel}"

    if [[ ! -f $dest ]]; then
      action="CREATE"
    elif cmp -s "$source" "$dest"; then
      action="NOOP-IDENTICAL"
    elif [[ $mode == "reset" ]]; then
      action="OVERWRITE-WITH-BACKUP"
    elif [[ $category == "devcontainer" && $internal == true ]]; then
      action="OVERWRITE"
    else
      action="SKIP-EXISTS"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$action" "$category" "$name" "$internal" "$source" "$dest"
  done < <(find "$src_dir" -type f | sort)
}
