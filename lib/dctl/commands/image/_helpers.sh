# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_IMAGE_HELPERS_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_IMAGE_HELPERS_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh

discover_image_targets() {
  local targets=()
  shopt -s nullglob
  local dir name
  for dir in "$DCTL_IMAGES_DIR"/*/; do
    if [[ -f "${dir}Containerfile" ]]; then
      name="$(basename "$dir")"
      targets+=("$name")
    fi
  done
  shopt -u nullglob

  printf '%s\n' "${targets[@]}"
}

resolve_containerfile() {
  local target="$1"
  local user_path
  user_path="$(config_image_path "$target")"
  if [[ -f $user_path ]]; then
    printf '%s\n' "$user_path"
    return 0
  fi
  return 1
}

get_image_tag() {
  printf 'devimg/%s:latest\n' "$1"
}

ensure_image_dir_exists() {
  if [[ ! -d $DCTL_IMAGES_DIR ]]; then
    log "No user image config found"
    log "Run: dctl deploy image <name> or dctl deploy --all-images"
    return 1
  fi
}
