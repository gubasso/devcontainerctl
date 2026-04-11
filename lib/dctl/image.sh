# shellcheck shell=bash
# Image commands for dctl (sourced, not executed directly)

[[ -n "${_DCTL_IMAGE_LOADED:-}" ]] && return 0
readonly _DCTL_IMAGE_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/common.sh"
# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/auth.sh"

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

discover_image_targets() {
  local targets=()
  shopt -s nullglob
  local dir name
  for dir in "$DCTL_IMAGES_DIR"/*/; do
    if [[ -f "${dir}Dockerfile" ]]; then
      name="$(basename "$dir")"
      targets+=("$name")
    fi
  done
  shopt -u nullglob

  printf '%s\n' "${targets[@]}"
}

resolve_dockerfile() {
  local target="$1"
  local user_path
  user_path="$(config_image_path "$target")"
  if [[ -f "$user_path" ]]; then
    printf '%s\n' "$user_path"
    return 0
  fi
  return 1
}

get_image_tag() {
  printf 'devimg/%s:latest\n' "$1"
}

ensure_image_dir_exists() {
  if [[ ! -d "$DCTL_IMAGES_DIR" ]]; then
    log "No user image config found"
    log "Run: dctl deploy image <name> or dctl deploy --all-images"
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
      err "No user image config found in $DCTL_IMAGES_DIR. Run: dctl deploy image <name> or dctl deploy --all-images"
    fi
  elif [[ ${#targets[@]} -eq 0 ]]; then
    local available=()
    local picked
    mapfile -t available < <(discover_image_targets)
    if [[ ${#available[@]} -eq 0 ]]; then
      err "No user image config found in $DCTL_IMAGES_DIR. Run: dctl deploy image <name> or dctl deploy --all-images"
    fi
    if ! command -v fzf >/dev/null 2>&1; then
      err "fzf not found. Install fzf or specify targets explicitly."
    fi
    if [[ ! -t 0 ]]; then
      err "Interactive mode requires a terminal. Use --all or specify targets explicitly."
    fi
    if ! picked="$(printf '%s\n' "${available[@]}" | _fzf_pick \
      "Select image to build: " \
      "ENTER: confirm, ESC: cancel")"; then
      return 0
    fi
    targets=("$picked")
  fi

  local target
  for target in "${targets[@]}"; do
    if ! resolve_dockerfile "$target" >/dev/null 2>&1; then
      printf '\033[1;31mERROR:\033[0m Unknown image: %s (not seeded in %s)\n' "$target" "$DCTL_IMAGES_DIR" >&2
      printf "Run: dctl deploy image <name> or dctl deploy --all-images\n" >&2
      printf 'Available images:\n' >&2
      discover_image_targets | sed 's/^/  /' >&2
      exit 1
    fi
  done

  local username
  username="${USER:-$(id -un)}"
  local -a build_args
  build_args=(--build-arg "USERNAME=${username}" --build-arg "USER_UID=$(id -u)" --build-arg "USER_GID=$(id -g)")

  # GitHub token for mise installs (avoids 60 req/hr anonymous rate limit)
  local -a secret_flag=()
  local gh_token_file=""
  if [[ "$dry_run" != true ]]; then
    local gh_token
    if gh_token=$(_extract_gh_token 2>/dev/null) && [[ -n "$gh_token" ]]; then
      gh_token_file=$(mktemp)
      printf '%s' "$gh_token" > "$gh_token_file"
      secret_flag=(--secret "id=gh_token,src=${gh_token_file}")
    else
      warn "No GitHub token found — builds may hit API rate limits (see: gh auth login)"
    fi
  fi

  local -a failed
  failed=()

  for target in "${targets[@]}"; do
    local tag
    tag="$(get_image_tag "$target")"

    local -a refresh_flag
    refresh_flag=()
    if [[ "$target" == "agents" && "$refresh_agents" == true ]]; then
      refresh_flag=(--build-arg "CACHEBUST_AGENTS=$(date +%s)")
    fi

    if [[ "$dry_run" == true ]]; then
      log "[dry-run] Would build: $tag"
      if [[ "$full_rebuild" == true ]]; then
        log "[dry-run]   flags: --no-cache (--pull applies to agents only)"
      fi
      if [[ ${#refresh_flag[@]} -gt 0 ]]; then
        log "[dry-run]   flags: --refresh-agents (cache-bust agent CLI layers)"
      fi
      continue
    fi

    local dockerfile_path
    dockerfile_path="$(resolve_dockerfile "$target")"
    local build_context
    build_context="$(dirname "$dockerfile_path")"
    log "Building ${tag} from ${build_context}/"

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
      "${build_args[@]}" \
      "${secret_flag[@]}" \
      -t "$tag" \
      "${build_context}/"; then
      warn "Failed to build: $target"
      failed+=("$target")
    fi
  done

  [[ -n "$gh_token_file" ]] && rm -f "$gh_token_file"

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
