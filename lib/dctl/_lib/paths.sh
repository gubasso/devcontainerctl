# shellcheck shell=bash

[[ -n ${_DCTL_LIB_PATHS_LOADED:-} ]] && return 0
readonly _DCTL_LIB_PATHS_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
: "${DCTL_VERSION:=dev}"
: "${WORKSPACE_FOLDER:=$PWD}"
WORKSPACE_FOLDER="$(cd -- "$WORKSPACE_FOLDER" && pwd -P)"
: "${IMAGES_DIR:=${XDG_DATA_HOME:-$HOME/.local/share}/dctl/images}"
: "${DEVCONTAINERS_DIR:=${XDG_DATA_HOME:-$HOME/.local/share}/dctl/devcontainers}"
: "${DCTL_CONFIG_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/dctl}"
: "${DCTL_CACHE_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/dctl}"
: "${DCTL_DEVCONTAINER_CACHE_DIR:=${DCTL_CACHE_DIR}/devcontainer}"
: "${DCTL_DEVCONTAINER_DIR:=${DCTL_CONFIG_DIR}/devcontainer}"
: "${DCTL_IMAGES_DIR:=${DCTL_CONFIG_DIR}/images}"
: "${DCTL_SCHEMAS_DIR:=${XDG_DATA_HOME:-$HOME/.local/share}/dctl/schemas}"

readonly DCTL_VERSION
readonly WORKSPACE_FOLDER
readonly IMAGES_DIR
readonly DEVCONTAINERS_DIR
readonly DCTL_CONFIG_DIR
readonly DCTL_CACHE_DIR
readonly DCTL_DEVCONTAINER_CACHE_DIR
readonly DCTL_DEVCONTAINER_DIR
readonly DCTL_IMAGES_DIR
readonly DCTL_SCHEMAS_DIR

workspace_path() {
  printf '%s\n' "$WORKSPACE_FOLDER"
}

workspace_devcontainer_dir() {
  printf '%s/.devcontainer\n' "$WORKSPACE_FOLDER"
}

workspace_devcontainer_file() {
  printf '%s/devcontainer.json\n' "$(workspace_devcontainer_dir)"
}

devcontainer_cache_path_for_manifest() {
  local name="$1"
  printf '%s/%s/devcontainer.json\n' "$DCTL_DEVCONTAINER_CACHE_DIR" "$name"
}

config_devcontainer_path() {
  local name="$1"
  printf '%s/%s/devcontainer.json\n' "$DCTL_DEVCONTAINER_DIR" "$name"
}

installed_compose_manifest_path() {
  local name="$1"
  printf '%s/%s.yaml\n' "$DEVCONTAINERS_DIR" "$name"
}

config_compose_manifest_path() {
  local name="$1"
  printf '%s/%s.yaml\n' "$DCTL_DEVCONTAINER_DIR" "$name"
}

config_image_path() {
  local name="$1"
  printf '%s/%s/Containerfile\n' "$DCTL_IMAGES_DIR" "$name"
}

installed_image_path() {
  local name="$1"
  printf '%s/%s/Containerfile\n' "$IMAGES_DIR" "$name"
}
