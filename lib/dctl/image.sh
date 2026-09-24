# shellcheck shell=bash
# Image commands for dctl (sourced, not executed directly)

[[ -n ${_DCTL_IMAGE_LOADED:-} ]] && return 0
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

# Split one Dockerfile line into its FROM reference and its stage alias.
# Prints "<reference>\t<alias>" (the alias may be empty) and returns 1 when the
# line is not a FROM instruction. Dockerfile keywords are case-insensitive, so
# `from` and `as` parse the same as `FROM` and `AS`.
# Reference: https://docs.docker.com/reference/dockerfile/#from
_image_from_line() {
  local line="$1"
  local trimmed="${line#"${line%%[![:space:]]*}"}"
  [[ $trimmed =~ ^[Ff][Rr][Oo][Mm][[:space:]] ]] || return 1

  local -a words=()
  read -r -a words <<<"$trimmed"

  # Skip flags such as --platform=<platform> to reach the image reference.
  local i=1
  while [[ $i -lt ${#words[@]} && ${words[$i]} == --* ]]; do
    i=$((i + 1))
  done
  [[ $i -lt ${#words[@]} ]] || return 1

  local ref="${words[$i]}"
  local stage=""
  local as_index=$((i + 1))
  if [[ $as_index -lt ${#words[@]} && ${words[$as_index],,} == "as" && $((as_index + 1)) -lt ${#words[@]} ]]; then
    stage="${words[$((as_index + 1))]}"
  fi

  printf '%s\t%s\n' "$ref" "$stage"
}

# Classify every FROM reference of a deployed managed image. Prints one
# "parent <name>" line per managed base and one "external <reference>" line per
# pullable outside base, in file order.
#
# The grammar is literal on purpose. dctl orders a graph it can read without
# expanding shell or build variables, so only `FROM devimg/<name>:latest` names
# a managed parent, every other `devimg/` spelling is refused rather than
# misread as external, and any reference holding `$` is refused outright. A
# same-file stage alias and `scratch` name nothing pullable and are dropped.
_image_from_refs() {
  local name="$1"
  local dockerfile
  if ! dockerfile="$(resolve_dockerfile "$name")"; then
    printf '\033[1;31mERROR:\033[0m Unknown image: %s (not seeded in %s)\n' "$name" "$DCTL_IMAGES_DIR" >&2
    return 1
  fi

  local -A aliases=()
  local line parsed stage
  while IFS= read -r line || [[ -n $line ]]; do
    parsed="$(_image_from_line "$line")" || continue
    stage="${parsed#*$'\t'}"
    [[ -n $stage ]] && aliases["${stage,,}"]=1
  done <"$dockerfile"

  local lineno=0
  local ref managed
  while IFS= read -r line || [[ -n $line ]]; do
    lineno=$((lineno + 1))
    parsed="$(_image_from_line "$line")" || continue
    ref="${parsed%%$'\t'*}"

    if [[ $ref == *'$'* ]]; then
      err "${dockerfile}:${lineno}: dctl reads managed parents from literal \`FROM devimg/<name>:latest\` lines; a variable reference cannot be ordered"
    fi

    if [[ -n ${aliases["${ref,,}"]:-} ]]; then
      continue
    fi

    if [[ $ref == devimg/* ]]; then
      managed="${ref#devimg/}"
      if [[ $managed != *:latest || ${managed%:latest} == */* || -z ${managed%:latest} ]]; then
        err "${dockerfile}:${lineno}: unsupported managed parent \`${ref}\`; dctl orders only literal \`FROM devimg/<name>:latest\` lines"
      fi
      printf 'parent %s\n' "${managed%:latest}"
      continue
    fi

    [[ $ref == "scratch" ]] && continue
    printf 'external %s\n' "$ref"
  done <"$dockerfile"
}

# Managed parents of one image, in file order, each name once.
_image_parents() {
  local refs
  refs="$(_image_from_refs "$1")" || return 1

  local -A seen=()
  local entry parent
  while IFS= read -r entry; do
    [[ $entry == parent\ * ]] || continue
    parent="${entry#parent }"
    [[ -n ${seen[$parent]:-} ]] && continue
    seen["$parent"]=1
    printf '%s\n' "$parent"
  done <<<"$refs"
}

# Pullable outside bases of one image, in file order, each reference once.
_image_external_bases() {
  local refs
  refs="$(_image_from_refs "$1")" || return 1

  local -A seen=()
  local entry ref
  while IFS= read -r entry; do
    [[ $entry == external\ * ]] || continue
    ref="${entry#external }"
    [[ -n ${seen[$ref]:-} ]] && continue
    seen["$ref"]=1
    printf '%s\n' "$ref"
  done <<<"$refs"
}

# One node of the depth-first walk in _order_image_targets. It reads and writes
# that function's locals through dynamic scope, so it is never called alone.
_visit_image_target() {
  local name="$1"
  local child="${2:-}"

  if [[ -n ${_image_on_stack["$name"]:-} ]]; then
    err "image dependency cycle: ${_image_stack[*]} -> ${name}"
  fi
  [[ -n ${_image_visited["$name"]:-} ]] && return 0

  if ! resolve_dockerfile "$name" >/dev/null 2>&1; then
    if [[ -n $child ]]; then
      err "parent \`${name}\` of \`${child}\` is not deployed; run \`dctl deploy image ${name}\`"
    fi
    err "Unknown image: ${name} (not seeded in ${DCTL_IMAGES_DIR})"
  fi

  _image_on_stack["$name"]=1
  _image_stack+=("$name")

  local parents parent
  parents="$(_image_parents "$name")" || exit 1
  while IFS= read -r parent; do
    [[ -n $parent ]] || continue
    _visit_image_target "$parent" "$name"
  done <<<"$parents"

  unset "_image_on_stack[$name]"
  unset '_image_stack[-1]'
  _image_visited["$name"]=1
  _image_ordered+=("$name")
}

# Expand the requested targets to their full managed ancestor closure, every
# parent before its child and every name once. Where the graph leaves two names
# free, they come out in alphabetical order. Reads no Docker daemon, so a dry
# run computes the whole order on a host without Docker.
_order_image_targets() {
  local -A _image_visited=()
  local -A _image_on_stack=()
  local -a _image_stack=()
  local -a _image_ordered=()

  local -a roots=()
  mapfile -t roots < <(printf '%s\n' "$@" | LC_ALL=C sort -u)

  local root
  for root in "${roots[@]}"; do
    [[ -n $root ]] || continue
    _visit_image_target "$root"
  done

  printf '%s\n' "${_image_ordered[@]}"
}

resolve_dockerfile() {
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

cmd_image_list() {
  if ! ensure_image_dir_exists; then
    return 0
  fi

  discover_image_targets
}

# Pull each literal external base of one image, once per cmd_image_build run.
# It reads that function's `pulled` and `dry_run` locals through dynamic scope,
# so it is never called alone.
_pull_external_bases() {
  local target="$1"
  local refs ref
  refs="$(_image_external_bases "$target")" || exit 1

  while IFS= read -r ref; do
    [[ -n $ref ]] || continue
    if [[ -n ${pulled["$ref"]:-} ]]; then
      continue
    fi
    pulled["$ref"]=1
    if [[ $dry_run == true ]]; then
      log "[dry-run]   would pull external base: $ref"
      continue
    fi
    log "Pulling external base: $ref"
    docker pull "$ref" || warn "Failed to pull ${ref}; building from the local cache"
  done <<<"$refs"
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

  # --full-rebuild means "from scratch, and pull the latest base" (ADR-0026's
  # "full rebuild = latest"). It must NOT also mean "every image": with explicit
  # targets that silently discarded them and rebuilt everything --no-cache, so
  # the `agents` in `dctl image build --full-rebuild agents` — the recovery
  # command printed by nix-reconcile.sh — was ignored. Only imply --all when no
  # target was named.
  if [[ $full_rebuild == true ]]; then
    no_cache=true
    if [[ ${#targets[@]} -eq 0 ]]; then
      all=true
    fi
  fi

  if [[ "$(id -u)" -eq 0 ]]; then
    err "Do not run as root (would bake UID 0 into images)"
  fi

  if [[ $dry_run != true ]]; then
    require_cmd docker
    if ! docker info >/dev/null 2>&1; then
      err "Docker daemon not running or not accessible"
    fi
    if ! docker buildx version >/dev/null 2>&1; then
      err "docker buildx not found (required for BuildKit builds)"
    fi
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
  if [[ $dry_run != true ]]; then
    local gh_token
    if gh_token=$(_extract_gh_token 2>/dev/null) && [[ -n $gh_token ]]; then
      gh_token_file=$(mktemp)
      printf '%s' "$gh_token" >"$gh_token_file"
      secret_flag=(--secret "id=gh_token,src=${gh_token_file}")
    else
      warn "No GitHub token found — builds may hit API rate limits (see: gh auth login)"
    fi
  fi

  # The requested names are roots; the build walks their whole managed ancestor
  # closure, parents first. The closure is computed for a dry run too, so the
  # printed order needs no Docker daemon.
  local ordered_out
  if ! ordered_out="$(_order_image_targets "${targets[@]}")"; then
    exit 1
  fi
  local -a ordered=()
  mapfile -t ordered <<<"$ordered_out"

  local -A requested=()
  for target in "${targets[@]}"; do
    requested["$target"]=1
  done

  local -a failed=()
  local -a blocked=()
  # name -> the failed ancestor that stopped it, itself for a direct failure.
  local -A stopped_by=()
  local -A pulled=()

  for target in "${ordered[@]}"; do
    local tag
    tag="$(get_image_tag "$target")"

    local parents parent blocker=""
    parents="$(_image_parents "$target")" || exit 1
    while IFS= read -r parent; do
      [[ -n $parent ]] || continue
      if [[ -n ${stopped_by["$parent"]:-} ]]; then
        blocker="${stopped_by["$parent"]}"
        break
      fi
    done <<<"$parents"

    # A stale local tag for a parent that just failed is not a base to build on.
    if [[ -n $blocker ]]; then
      warn "Skipping ${target}: blocked by failed parent ${blocker}"
      blocked+=("$target")
      stopped_by["$target"]="$blocker"
      continue
    fi

    local -a refresh_flag
    refresh_flag=()
    if [[ $target == "agents" && $refresh_agents == true ]]; then
      refresh_flag=(--build-arg "CACHEBUST_AGENTS=$(date +%s)")
    fi

    if [[ $dry_run == true ]]; then
      log "[dry-run] Would build: $tag"
      if [[ $full_rebuild == true ]]; then
        log "[dry-run]   flags: --no-cache"
        _pull_external_bases "$target"
      fi
      if [[ ${#refresh_flag[@]} -gt 0 ]]; then
        log "[dry-run]   flags: --refresh-agents (cache-bust agent CLI layers)"
      fi
      continue
    fi

    # An ancestor pulled in by the closure is built only when it is missing.
    # A name the operator asked for is always rebuilt.
    if [[ $full_rebuild != true && -z ${requested["$target"]:-} ]] \
      && docker image inspect "$tag" >/dev/null 2>&1; then
      log "skipping ${target}: present, not requested"
      continue
    fi

    # "Full rebuild = latest" pulls each literal external base by name. Passing
    # --pull to docker buildx build instead would apply to the whole Dockerfile
    # and try to resolve a local managed parent such as devimg/base:latest
    # against a registry.
    if [[ $full_rebuild == true ]]; then
      _pull_external_bases "$target"
    fi

    local dockerfile_path
    dockerfile_path="$(resolve_dockerfile "$target")"
    local build_context
    build_context="$(dirname "$dockerfile_path")"
    log "Building ${tag} from ${build_context}/"

    local -a no_cache_flag
    no_cache_flag=()
    if [[ $no_cache == true ]]; then
      no_cache_flag=(--no-cache)
    fi

    if ! docker buildx build --load \
      "${no_cache_flag[@]}" \
      "${refresh_flag[@]}" \
      "${build_args[@]}" \
      "${secret_flag[@]}" \
      -t "$tag" \
      "${build_context}/"; then
      warn "Failed to build: $target"
      failed+=("$target")
      stopped_by["$target"]="$target"
    fi
  done

  [[ -n $gh_token_file ]] && rm -f "$gh_token_file"

  if [[ $dry_run == true ]]; then
    log "Dry-run complete"
    return 0
  fi
  if [[ ${#failed[@]} -gt 0 ]]; then
    local message="Failed to build: ${failed[*]}"
    if [[ ${#blocked[@]} -gt 0 ]]; then
      message+=" (blocked by a failed parent: ${blocked[*]})"
    fi
    err "$message"
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
