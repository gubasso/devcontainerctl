# shellcheck shell=bash
# Image commands for dctl (sourced, not executed directly)

[[ -n "${_DCTL_IMAGE_LOADED:-}" ]] && return 0
readonly _DCTL_IMAGE_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/common.sh"

usage_image() {
  cat <<'EOF'
Usage: dctl image <command> [options]

Commands:
  build [OPTIONS] [IMAGE...]
      Build devcontainer base images from $XDG_DATA_HOME/dctl/images.
      If no image is specified, launches interactive fzf selection.

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

discover_image_targets() {
  local targets=()
  shopt -s nullglob
  local dir
  for dir in "$IMAGES_DIR"/*/; do
    if [[ -f "${dir}Dockerfile" ]]; then
      targets+=("$(basename "$dir")")
    fi
  done
  shopt -u nullglob

  printf '%s\n' "${targets[@]}"
}

get_image_tag() {
  printf 'devimg/%s:latest\n' "$1"
}

select_image_targets() {
  local available=()
  mapfile -t available < <(discover_image_targets)

  if [[ ${#available[@]} -eq 0 ]]; then
    err "No images found in $IMAGES_DIR (no directories with Dockerfiles)"
  fi
  if ! command -v fzf >/dev/null 2>&1; then
    err "fzf not found. Install fzf or specify targets explicitly."
  fi
  if [[ ! -t 0 ]]; then
    err "Interactive mode requires a terminal. Use --all or specify targets explicitly."
  fi

  local selected
  if ! selected=$(printf '%s\n' "${available[@]}" | fzf --multi \
    --height=~50% \
    --layout=reverse \
    --border \
    --prompt="Select images to build: " \
    --header="TAB: multi-select, ENTER: confirm, ESC: cancel"); then
    return 1
  fi

  printf '%s\n' "$selected"
}

ensure_image_dir_exists() {
  if [[ ! -d "$IMAGES_DIR" ]]; then
    log "Images directory not found: $IMAGES_DIR"
    log "Install with: make install"
    return 1
  fi
}

cmd_image_list() {
  if ! ensure_image_dir_exists; then
    return 0
  fi

  discover_image_targets
}

cmd_image_build() {
  local all=false
  local full_rebuild=false
  local refresh_agents=false
  local no_cache=false
  local dry_run=false
  local targets=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        usage_image
        return 0
        ;;
      --all)
        all=true
        shift
        ;;
      --full-rebuild)
        full_rebuild=true
        shift
        ;;
      --refresh-agents)
        refresh_agents=true
        shift
        ;;
      --dry-run | -n)
        dry_run=true
        shift
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          targets+=("$1")
          shift
        done
        ;;
      *)
        targets+=("$1")
        shift
        ;;
    esac
  done

  if [[ "$full_rebuild" == true ]]; then
    all=true
    no_cache=true
  fi

  if [[ "$(id -u)" -eq 0 ]]; then
    err "Do not run as root (would bake UID 0 into images)"
  fi

  if [[ ! -d "$IMAGES_DIR" ]]; then
    if [[ "$dry_run" == true ]]; then
      log "Images directory not found: $IMAGES_DIR"
      log "Install with: make install"
      return 0
    fi
    printf 'Install with: make install\n' >&2
    err "Images directory not found: $IMAGES_DIR"
  fi

  if [[ "$dry_run" != true ]]; then
    require_cmd docker
    if ! docker info >/dev/null 2>&1; then
      err "Docker daemon not running or not accessible"
    fi
    if ! docker buildx version >/dev/null 2>&1; then
      err "docker buildx not found (required for BuildKit builds)"
    fi
  fi

  if [[ "$all" == true ]]; then
    mapfile -t targets < <(discover_image_targets)
    if [[ ${#targets[@]} -eq 0 ]]; then
      err "No images found in $IMAGES_DIR (no directories with Dockerfiles)"
    fi
  elif [[ ${#targets[@]} -eq 0 ]]; then
    if ! mapfile -t targets < <(select_image_targets); then
      return 0
    fi
    if [[ ${#targets[@]} -eq 0 ]]; then
      return 0
    fi
  fi

  local target
  for target in "${targets[@]}"; do
    if [[ ! -d "$IMAGES_DIR/$target" || ! -f "$IMAGES_DIR/$target/Dockerfile" ]]; then
      printf '\033[1;31mERROR:\033[0m Unknown image: %s\n' "$target" >&2
      printf 'Available images:\n' >&2
      discover_image_targets | sed 's/^/  /' >&2
      exit 1
    fi
  done

  local username dotfiles_dir
  username="${USER:-$(id -un)}"
  dotfiles_dir="${DOTFILES:-${HOME}/.dotfiles}"
  local -a build_args
  build_args=(--build-arg "USERNAME=${username}" --build-arg "USER_UID=$(id -u)" --build-arg "USER_GID=$(id -g)")

  local -a failed
  failed=()

  cd "$IMAGES_DIR" || exit 1

  for target in "${targets[@]}"; do
    local tag
    tag="$(get_image_tag "$target")"

    local -a extra_contexts
    extra_contexts=()
    if [[ "$target" == "agents" || "$target" == "zig-dev" ]]; then
      if [[ -d "$dotfiles_dir" ]]; then
        extra_contexts=(--build-context "dotfiles=${dotfiles_dir}")
      elif [[ "$dry_run" == true ]]; then
        warn "Dotfiles not found at ${dotfiles_dir} - agents/zig-dev build would fail"
      else
        err "Dotfiles not found at ${dotfiles_dir} - set DOTFILES= or ensure ~/.dotfiles exists"
      fi
    fi

    local -a refresh_flag
    refresh_flag=()
    if [[ "$target" == "agents" && "$refresh_agents" == true ]]; then
      refresh_flag=(--build-arg "CACHEBUST_AGENTS=$(date +%s)")
    fi

    if [[ "$dry_run" == true ]]; then
      log "[dry-run] Would build: $tag"
      if [[ ${#extra_contexts[@]} -gt 0 ]]; then
        log "[dry-run]   dotfiles context: $dotfiles_dir"
      fi
      if [[ "$full_rebuild" == true ]]; then
        log "[dry-run]   flags: --no-cache (--pull applies to agents only)"
      fi
      if [[ ${#refresh_flag[@]} -gt 0 ]]; then
        log "[dry-run]   flags: --refresh-agents (cache-bust agent CLI layers)"
      fi
      continue
    fi

    log "Building ${tag} from ./${target}/"

    local -a pull_flag
    pull_flag=()
    if [[ "$target" == "agents" && "$all" == true ]]; then
      pull_flag=(--pull)
    fi

    local -a no_cache_flag
    no_cache_flag=()
    if [[ "$no_cache" == true ]]; then
      no_cache_flag=(--no-cache)
    fi

    if ! docker buildx build --load \
      "${pull_flag[@]}" \
      "${no_cache_flag[@]}" \
      "${refresh_flag[@]}" \
      "${extra_contexts[@]}" \
      "${build_args[@]}" \
      -t "$tag" \
      "./${target}/"; then
      warn "Failed to build: $target"
      failed+=("$target")
    fi
  done

  if [[ "$dry_run" == true ]]; then
    log "Dry-run complete"
    return 0
  fi
  if [[ ${#failed[@]} -gt 0 ]]; then
    err "Failed to build: ${failed[*]}"
  fi

  log "Build complete"
  docker images | grep -E '^devimg/' || true
}

main_image() {
  local command="${1:-help}"

  case "$command" in
    build)
      shift
      cmd_image_build "$@"
      ;;
    list)
      shift
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
