# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_IMAGE_BUILD_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_IMAGE_BUILD_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require _lib/fzf.sh
__dctl_require commands/image/_helpers.sh
__dctl_require runtime/common.sh
__dctl_require runtime/krun.sh

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

  if [[ $full_rebuild == true ]]; then
    all=true
    no_cache=true
  fi

  if [[ "$(id -u)" -eq 0 ]]; then
    err "Do not run as root (would bake UID 0 into images)"
  fi

  if [[ $all == true ]]; then
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
    if ! resolve_containerfile "$target" >/dev/null 2>&1; then
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

  local -a failed
  failed=()

  for target in "${targets[@]}"; do
    local tag
    tag="$(get_image_tag "$target")"

    local -a refresh_flag
    refresh_flag=()
    if [[ $target == "agents" && $refresh_agents == true ]]; then
      refresh_flag=(--build-arg "CACHEBUST_AGENTS=$(date +%s)")
    fi

    if [[ $dry_run == true ]]; then
      log "[dry-run] Would build: $tag"
      if [[ $full_rebuild == true ]]; then
        log "[dry-run]   flags: --no-cache (--pull applies to agents only)"
      fi
      if [[ ${#refresh_flag[@]} -gt 0 ]]; then
        log "[dry-run]   flags: --refresh-agents (cache-bust agent CLI layers)"
      fi
      continue
    fi

    local containerfile_path
    containerfile_path="$(resolve_containerfile "$target")"
    local build_context
    build_context="$(dirname "$containerfile_path")"
    log "Building ${tag} from ${build_context}/"

    local -a pull_flag
    pull_flag=()
    if [[ $target == "agents" && $all == true ]]; then
      pull_flag=(--pull)
    fi

    local -a no_cache_flag
    no_cache_flag=()
    if [[ $no_cache == true ]]; then
      no_cache_flag=(--no-cache)
    fi

    if ! rt_build "$target" "$build_context" \
      "${pull_flag[@]}" \
      "${no_cache_flag[@]}" \
      "${refresh_flag[@]}" \
      "${build_args[@]}"; then
      warn "Failed to build: $target"
      failed+=("$target")
    fi
  done

  if [[ $dry_run == true ]]; then
    log "Dry-run complete"
    return 0
  fi
  if [[ ${#failed[@]} -gt 0 ]]; then
    err "Failed to build: ${failed[*]}"
  fi

  log "Build complete"
  podman images --filter "reference=devimg/*" || true
}
