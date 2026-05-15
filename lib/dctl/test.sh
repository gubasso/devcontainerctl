# shellcheck shell=bash
# Setup smoke-test command for dctl (sourced, not executed directly)

[[ -n ${_DCTL_TEST_LOADED:-} ]] && return 0
readonly _DCTL_TEST_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/common.sh"
# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/ws.sh"
# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/image.sh"

usage_test() {
  cat <<'EOF'
Usage: dctl test [options]

Validate the current workspace devcontainer setup with a smoke test.

Options:
  --help, -h    Show this help text

Examples:
  dctl test
EOF
}

_check_names=()
_check_results=()

check_pass() {
  _check_names+=("$1")
  _check_results+=("PASS")
  printf '\033[1;32mPASS:\033[0m %s\n' "$1"
}

check_fail() {
  _check_names+=("$1")
  _check_results+=("FAIL")
  printf '\033[1;31mFAIL:\033[0m %s\n' "$1"
}

_print_summary() {
  local passed=0 failed=0
  local i

  printf '\n\033[1m── Summary ──────────────────────────────\033[0m\n'
  if [[ -n ${DCTL_CONFIG_STATUS:-} ]]; then
    case "$DCTL_CONFIG_STATUS" in
      cached) printf '  \033[1;36mℹ\033[0m Config: using cached devcontainer.json\n' ;;
      generated) printf '  \033[1;36mℹ\033[0m Config: generated new devcontainer.json\n' ;;
      existing) printf '  \033[1;36mℹ\033[0m Config: using existing registered config\n' ;;
    esac
  fi
  for i in "${!_check_names[@]}"; do
    if [[ ${_check_results[$i]} == "PASS" ]]; then
      printf '  \033[1;32m✔\033[0m %s\n' "${_check_names[$i]}"
      passed=$((passed + 1))
    else
      printf '  \033[1;31m✘\033[0m %s\n' "${_check_names[$i]}"
      failed=$((failed + 1))
    fi
  done
  printf '\033[1m── %d passed, %d failed ──────────────────\033[0m\n' "$passed" "$failed"
}

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

cmd_test() {
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

main_test() {
  warn "'dctl test' will be rewired to podman in Phase 2; use 'dctl doctor' to verify host setup."
  cmd_test "$@"
}
