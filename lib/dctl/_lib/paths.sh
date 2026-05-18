# shellcheck shell=bash

[[ -n ${_DCTL_LIB_PATHS_LOADED:-} ]] && return 0
readonly _DCTL_LIB_PATHS_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
: "${DCTL_VERSION:=dev}"
: "${WORKSPACE_FOLDER:=$PWD}"
WORKSPACE_FOLDER="$(cd -- "$WORKSPACE_FOLDER" && pwd -P)"

# DCTL_HOME, when set, redirects config/cache/data roots under one
# dev/test prefix. Individual DCTL_*_DIR / IMAGES_DIR overrides still
# take precedence; XDG_* fallbacks apply when DCTL_HOME is unset.
# When running from a repo working tree (lib/dctl's parent contains
# the seed images/devcontainers/schemas trio), DCTL_DATA_DIR defaults
# to that repo root so `dctl init` can seed without `make install`.
if [[ -n ${DCTL_HOME:-} ]]; then
  : "${DCTL_CONFIG_DIR:=${DCTL_HOME}/config}"
  : "${DCTL_CACHE_DIR:=${DCTL_HOME}/cache}"
  if [[ -z ${DCTL_DATA_DIR:-} ]]; then
    _dctl_repo_root="$(cd -- "${DCTL_LIB_DIR}/../.." && pwd -P)"
    if [[ -d ${_dctl_repo_root}/images && -d ${_dctl_repo_root}/devcontainers && -d ${_dctl_repo_root}/schemas ]]; then
      DCTL_DATA_DIR="$_dctl_repo_root"
    else
      DCTL_DATA_DIR="${DCTL_HOME}/share"
    fi
    unset _dctl_repo_root
  fi
fi

: "${DCTL_CONFIG_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/dctl}"
: "${DCTL_CACHE_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/dctl}"
: "${DCTL_DATA_DIR:=${XDG_DATA_HOME:-$HOME/.local/share}/dctl}"

: "${IMAGES_DIR:=${DCTL_DATA_DIR}/images}"
: "${DEVCONTAINERS_DIR:=${DCTL_DATA_DIR}/devcontainers}"
: "${DCTL_SCHEMAS_DIR:=${DCTL_DATA_DIR}/schemas}"
: "${DCTL_DEVCONTAINER_CACHE_DIR:=${DCTL_CACHE_DIR}/devcontainer}"
: "${DCTL_DEVCONTAINER_DIR:=${DCTL_CONFIG_DIR}/devcontainer}"
: "${DCTL_IMAGES_DIR:=${DCTL_CONFIG_DIR}/images}"

readonly DCTL_VERSION
readonly WORKSPACE_FOLDER
readonly DCTL_CONFIG_DIR
readonly DCTL_CACHE_DIR
readonly DCTL_DATA_DIR
readonly IMAGES_DIR
readonly DEVCONTAINERS_DIR
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
