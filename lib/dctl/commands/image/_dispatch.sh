# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_IMAGE_DISPATCH_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_IMAGE_DISPATCH_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require commands/image/_helpers.sh

usage_image() {
  cat <<'EOF'
Usage: dctl image <command> [options]

Commands:
  build [OPTIONS] [IMAGE...]
      Build devcontainer base images from $XDG_CONFIG_HOME/dctl/images.
      If no image is specified, launches an interactive fzf picker over
      the deployed managed images under ~/.config/dctl/images/.

      Options:
        --all              Build all discovered images
        --full-rebuild     Rebuild all images from scratch
        --refresh-agents   Cache-bust the agents CLI layer
        --dry-run, -n      Show what would be built without building
        --help, -h         Show build help

  list
      List available images and exit.

  help
      Show this help text.

Examples:
  dctl image build
  dctl image build agents
  dctl image build --all
  dctl image build --full-rebuild
  dctl image build --refresh-agents agents
  dctl image build --dry-run
  dctl image list
EOF
}

main_image() {
  local command="${1:-help}"

  case "$command" in
    build)
      shift
      __dctl_require commands/image/build.sh
      cmd_image_build "$@"
      ;;
    list)
      shift
      __dctl_require commands/image/list.sh
      cmd_image_list "$@"
      ;;
    help | -h | --help)
      usage_image
      ;;
    *)
      err "Unknown image command: $command"
      ;;
  esac
}
