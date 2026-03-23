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

: "${DCTL_USER_IMAGES_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/dctl/images}"

discover_image_targets() {
  local -A seen=()
  local targets=()
  shopt -s nullglob
  local dir name
  # User image overrides first
  for dir in "$DCTL_USER_IMAGES_DIR"/*/; do
    if [[ -f "${dir}Dockerfile" ]]; then
      name="$(basename "$dir")"
      seen["$name"]=1
      targets+=("$name")
    fi
  done
  # Installed images (skipped if user override exists)
  for dir in "$IMAGES_DIR"/*/; do
    if [[ -f "${dir}Dockerfile" ]]; then
      name="$(basename "$dir")"
      if [[ -z "${seen[$name]:-}" ]]; then
        targets+=("$name")
      fi
    fi
  done
  shopt -u nullglob

  printf '%s\n' "${targets[@]}"
}

resolve_dockerfile() {
  local target="$1"
  local user_path="${DCTL_USER_IMAGES_DIR}/${target}/Dockerfile"
  if [[ -f "$user_path" ]]; then
    log "Using Dockerfile override from $user_path" >&2
    printf '%s\n' "$user_path"
    return 0
  fi
  local installed_path="${IMAGES_DIR}/${target}/Dockerfile"
  if [[ -f "$installed_path" ]]; then
    printf '%s\n' "$installed_path"
    return 0
  fi
  return 1
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
  if [[ ! -d "$IMAGES_DIR" && ! -d "$DCTL_USER_IMAGES_DIR" ]]; then
    log "No images directory found"
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
  local _registry_direct_dockerfile=""

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

  # Note: we don't fail early on missing image dirs because registry
  # direct-path Dockerfiles don't need them. Validation happens per-target.

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
      err "No images found (no directories with Dockerfiles)"
    fi
  elif [[ ${#targets[@]} -eq 0 ]]; then
    # Check project registry for a dockerfile target
    local canonical_name registry_dockerfile
    canonical_name="$(resolve_canonical_project_name)"
    registry_dockerfile="$(_registry_lookup_dockerfile "$canonical_name")"
    if [[ -n "$registry_dockerfile" ]]; then
      if [[ "$registry_dockerfile" == /* ]]; then
        # Direct path — validate and use directly
        [[ -f "$registry_dockerfile" ]] || err "Registry Dockerfile path does not exist: $registry_dockerfile"
        _registry_direct_dockerfile="$registry_dockerfile"
        targets=("__registry_direct__")
        log "Using Dockerfile from registry direct path: $registry_dockerfile"
      else
        # Managed target name
        targets=("$registry_dockerfile")
        log "Using Dockerfile target from registry: $registry_dockerfile"
      fi
    else
      if ! mapfile -t targets < <(select_image_targets); then
        return 0
      fi
      if [[ ${#targets[@]} -eq 0 ]]; then
        return 0
      fi
    fi
  fi

  local target
  for target in "${targets[@]}"; do
    [[ "$target" == "__registry_direct__" ]] && continue
    if ! resolve_dockerfile "$target" >/dev/null 2>&1; then
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
    # Handle registry direct-path Dockerfile
    if [[ "$target" == "__registry_direct__" && -n "$_registry_direct_dockerfile" ]]; then
      local direct_context
      direct_context="$(dirname "$_registry_direct_dockerfile")"
      local direct_tag
      direct_tag="devimg/$(basename "$direct_context"):latest"

      if [[ "$dry_run" == true ]]; then
        log "[dry-run] Would build: $direct_tag from $direct_context (direct path)"
        continue
      fi

      log "Building ${direct_tag} from ${_registry_direct_dockerfile}"
      if ! docker buildx build --load \
        "${build_args[@]}" \
        "${secret_flag[@]}" \
        -f "$_registry_direct_dockerfile" \
        -t "$direct_tag" \
        "$direct_context/"; then
        warn "Failed to build from direct path: $_registry_direct_dockerfile"
        failed+=("$target")
      fi
      continue
    fi

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
      "${extra_contexts[@]}" \
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
