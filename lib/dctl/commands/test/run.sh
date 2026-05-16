# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_TEST_RUN_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_TEST_RUN_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require _lib/json/strip_comments.sh
__dctl_require commands/ws/_helpers.sh
__dctl_require commands/image/_helpers.sh
__dctl_require commands/image/build.sh
__dctl_require commands/test/_summary.sh

extract_workspace_image() {
  local config_path="${1:-$(workspace_devcontainer_file)}"

  [[ -f $config_path ]] || return 1

  local image_line
  image_line="$(grep -m1 -E '^[[:space:]]*"image"[[:space:]]*:' "$config_path" || true)"
  [[ -n $image_line ]] || return 1

  sed -E 's/^[[:space:]]*"image"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' <<<"$image_line"
}

cleanup_test_workspace_containers() {
  list_ws_containers | xargs -r docker rm -f
}

_resolve_local_env() {
  local str="$1"
  while [[ $str =~ \$\{localEnv:([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
    local var_name="${BASH_REMATCH[1]}"
    local value="${!var_name-}"
    local match="${BASH_REMATCH[0]}"
    str="${str//"$match"/$value}"
  done
  printf '%s' "$str"
}

_extract_bind_mount_sources() {
  local config_path="$1"
  local stripped

  stripped="$(_strip_jsonc_comments "$config_path")" || return 1

  jq -r '
    (.mounts // [])[]
    | if type == "object" then
        if (.type // "") == "bind" then ((.source // .src) // empty) else empty end
      elif type == "string" then
        if test("(^|,)type=bind(,|$)") then
          (split(",")[] | select(test("^(source|src)=")) | sub("^(source|src)="; ""))
        else empty end
      else empty end
  ' <<<"$stripped"
}

check_bind_mount_sources() {
  local config_path="$1"

  if ! command -v jq >/dev/null 2>&1; then
    warn "jq not found; skipping bind mount source check"
    return 0
  fi

  local sources
  if ! sources="$(_extract_bind_mount_sources "$config_path")"; then
    check_fail "Failed to parse bind mounts from $config_path"
    return 1
  fi

  local -a missing_paths=()
  local -a unresolved=()
  local raw resolved
  while IFS= read -r raw; do
    [[ -n $raw ]] || continue
    resolved="$(_resolve_local_env "$raw")"
    if [[ -z $resolved ]]; then
      unresolved+=("$raw")
      continue
    fi
    [[ -e $resolved ]] || missing_paths+=("$resolved")
  done <<<"$sources"

  if [[ ${#missing_paths[@]} -eq 0 && ${#unresolved[@]} -eq 0 ]]; then
    check_pass "Bind mount sources exist on host"
    return 0
  fi

  check_fail "Missing bind mount source(s) on host"
  local path
  for path in "${missing_paths[@]}"; do
    printf '    - %s\n' "$path" >&2
  done
  for path in "${unresolved[@]}"; do
    printf '    - (unresolved) %s\n' "$path" >&2
  done
  if [[ ${#missing_paths[@]} -gt 0 ]]; then
    printf '  Create the missing path(s) on the host before running devcontainer up, e.g.:\n' >&2
    printf '    mkdir -p' >&2
    for path in "${missing_paths[@]}"; do
      printf ' %q' "$path"
    done >&2
    printf '\n' >&2
  fi
  if [[ ${#unresolved[@]} -gt 0 ]]; then
    printf '  Set the referenced localEnv variable(s) on the host before running devcontainer up.\n' >&2
  fi
  return 1
}

build_workspace_image_if_managed() {
  local cfg="${1:-$(workspace_devcontainer_file)}"
  local image
  image="$(extract_workspace_image "$cfg" || true)"

  if [[ -z $image ]]; then
    warn "No image field found in $cfg; skipping image build"
    return 0
  fi

  if [[ $image =~ ^devimg/([[:alnum:]._-]+):latest$ ]]; then
    local target="${BASH_REMATCH[1]}"
    if resolve_dockerfile "$target" >/dev/null 2>&1; then
      (cmd_image_build "$target")
      return $?
    fi
    warn "Managed image '$image' not deployed. Run: dctl deploy image ${target} or dctl deploy --all-images"
    return 1
  fi

  log "Skipping image build for external image: $image"
}

cmd_test_run() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help | -h)
        usage_test
        return 0
        ;;
      *)
        err "Unknown test option: $1"
        ;;
    esac
  done

  local config_path
  if ! config_path="$(resolve_devcontainer_config)"; then
    return 1
  fi

  _check_names=()
  _check_results=()
  local failures=0
  local docker_ready=false
  local devcontainer_ready=false
  local container_started=false

  if command -v docker >/dev/null 2>&1; then
    check_pass "docker command found"
    if docker info >/dev/null 2>&1; then
      check_pass "Docker daemon is accessible"
      docker_ready=true
    else
      check_fail "Docker daemon not running or not accessible"
      failures=$((failures + 1))
    fi
  else
    check_fail "Missing required command: docker"
    failures=$((failures + 1))
  fi

  if command -v devcontainer >/dev/null 2>&1; then
    check_pass "devcontainer command found"
    devcontainer_ready=true
  else
    check_fail "Missing required command: devcontainer"
    failures=$((failures + 1))
  fi

  if [[ $docker_ready == true && $devcontainer_ready == true ]]; then
    if build_workspace_image_if_managed "$config_path"; then
      check_pass "Workspace image is ready"
    else
      check_fail "Failed to build managed workspace image"
      failures=$((failures + 1))
    fi

    local bind_sources_ok=true
    if ! check_bind_mount_sources "$config_path"; then
      failures=$((failures + 1))
      bind_sources_ok=false
    fi

    if [[ $bind_sources_ok == true ]]; then
      if devcontainer up --workspace-folder "$WORKSPACE_FOLDER" --config "$config_path"; then
        check_pass "devcontainer up succeeded"
        container_started=true
      else
        check_fail "devcontainer up failed"
        failures=$((failures + 1))
      fi
    fi

    if [[ $container_started == true ]]; then
      if devcontainer exec --workspace-folder "$WORKSPACE_FOLDER" --config "$config_path" printf 'dctl-smoke\n' >/dev/null; then
        check_pass "devcontainer exec succeeded"
      else
        check_fail "devcontainer exec failed"
        failures=$((failures + 1))
      fi
    fi

    if cleanup_test_workspace_containers; then
      check_pass "Workspace containers cleaned up"
    else
      check_fail "Failed to clean up workspace containers"
      failures=$((failures + 1))
    fi
  fi

  _print_summary

  if [[ $failures -gt 0 ]]; then
    err "Smoke test failed with ${failures} check(s)"
  fi

  log "Smoke test passed"
}
