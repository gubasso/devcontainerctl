# shellcheck shell=bash
# Init command for dctl (sourced, not executed directly)

[[ -n ${_DCTL_INIT_LOADED:-} ]] && return 0
readonly _DCTL_INIT_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/common.sh"
# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/config.sh"
# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/image.sh"
# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/test.sh"

usage_init() {
  cat <<'EOF'
Usage: dctl init [options]

Register the current project against a deployed devcontainer config and run
the workspace smoke test.

Options:
  --devcontainer <name>                Use a specific deployed devcontainer
  --help, -h                           Show this help text

Examples:
  dctl init --devcontainer python
  dctl init
EOF
}

_discover_deployed_selectable_devcontainers() {
  local manifests=()
  shopt -s nullglob
  local f name
  for f in "$DCTL_DEVCONTAINER_DIR"/*.yaml; do
    name="$(basename "$f" .yaml)"
    manifests+=("$name")
  done
  shopt -u nullglob
  [[ ${#manifests[@]} -gt 0 ]] && printf '%s\n' "${manifests[@]}"
}

_select_deployed_devcontainer_interactive() {
  local -a available=()
  mapfile -t available < <(_discover_deployed_selectable_devcontainers)

  [[ ${#available[@]} -gt 0 ]] || err "No devcontainers deployed. Run: dctl deploy (or dctl deploy devcontainer <name>)"
  command -v fzf >/dev/null 2>&1 || err "fzf not found. Install fzf or pass --devcontainer <name>."
  [[ -t 0 ]] || err "Interactive init requires a terminal. Pass --devcontainer <name>."

  printf '%s\n' "${available[@]}" | _fzf_pick \
    "Select deployed devcontainer: " \
    "ENTER: confirm, ESC: cancel"
}

_infer_image_from_devcontainer_json() {
  local path="$1"
  local json jq_err

  require_cmd jq
  json="$(_strip_jsonc_comments "$path")" || return 1
  if ! jq_err="$(jq empty <<<"$json" 2>&1)"; then
    printf 'JSON syntax error in %s:\n  %s\n' "$path" "$jq_err" >&2
    return 1
  fi

  jq -r '.image // empty' <<<"$json"
}

_image_ref_to_name() {
  local image_ref="$1"
  if [[ $image_ref =~ ^devimg/([[:alnum:]._-]+):latest$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

ensure_image_available_for_devcontainer() {
  local devcontainer_name="$1"
  local config_path image_ref image_name

  DCTL_INIT_IMAGE_STATUS=""
  DCTL_INIT_IMAGE_REF=""

  # The image is declared in the merged config (typically the base layer), so
  # merge fresh to read it — there is no cached config to inspect.
  if ! config_path="$(generate_devcontainer "$devcontainer_name")"; then
    return 1
  fi
  image_ref="$(_infer_image_from_devcontainer_json "$config_path" || true)"

  DCTL_INIT_IMAGE_REF="$image_ref"
  if [[ -z $image_ref ]]; then
    DCTL_INIT_IMAGE_STATUS="no-image"
    return 0
  fi

  if ! image_name="$(_image_ref_to_name "$image_ref" 2>/dev/null)"; then
    DCTL_INIT_IMAGE_STATUS="external"
    log "Using external image from deployed config: $image_ref"
    return 0
  fi

  if [[ ! -f "$(config_image_path "$image_name")" ]]; then
    err "Image '$image_name' is not deployed. Run: dctl deploy image $image_name"
  fi

  require_cmd docker
  if docker image inspect "$image_ref" >/dev/null 2>&1; then
    DCTL_INIT_IMAGE_STATUS="already-built"
    return 0
  fi

  cmd_image_build "$image_name"
  DCTL_INIT_IMAGE_STATUS="built-now"
}

cmd_init() {
  local devcontainer=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --devcontainer)
        [[ $# -ge 2 ]] || err "--devcontainer requires a value"
        devcontainer="$2"
        shift 2
        ;;
      --help | -h)
        usage_init
        return 0
        ;;
      *)
        err "Unknown init option: $1"
        ;;
    esac
  done

  local -a available=()
  mapfile -t available < <(_discover_deployed_selectable_devcontainers)
  [[ ${#available[@]} -gt 0 ]] || err "No devcontainers deployed. Run: dctl deploy (or dctl deploy devcontainer <name>)"

  if [[ -z $devcontainer ]]; then
    devcontainer="$(_select_deployed_devcontainer_interactive)" || return $?
  fi

  _validate_deployed_devcontainer "$devcontainer"

  local canonical_name existing_manifest=""
  canonical_name="$(resolve_canonical_project_name)"

  # Warn on a manifest switch. Tolerate a legacy/invalid registry here: the
  # lookup runs _validate_registry, which would reject a legacy `devcontainer:`
  # key and exit — but register_project_defaults migrates it below, so swallow
  # the failure rather than aborting init.
  if command -v yq >/dev/null 2>&1; then
    existing_manifest="$(_registry_lookup_devcontainer_manifest "$canonical_name" 2>/dev/null || true)"
  fi
  if [[ -n $existing_manifest && $existing_manifest != "$devcontainer" ]]; then
    warn "Switching project '$canonical_name' from manifest '$existing_manifest' to '$devcontainer'"
  fi

  local deployed_config
  if ! deployed_config="$(generate_devcontainer "$devcontainer")"; then
    return 1
  fi

  ensure_image_available_for_devcontainer "$devcontainer"

  register_project_defaults "$canonical_name" "$devcontainer"

  local test_status="passed"
  if ! DCTL_CLI_CONFIG="$deployed_config" cmd_test; then
    test_status="failed"
  fi

  log ""
  log "=== dctl init summary ==="
  log "Project: $canonical_name"
  log "Devcontainer: $devcontainer"
  case "${DCTL_INIT_IMAGE_STATUS:-}" in
    already-built)
      log "Image status: already-built (${DCTL_INIT_IMAGE_REF})"
      ;;
    built-now)
      log "Image status: built-now (${DCTL_INIT_IMAGE_REF})"
      ;;
    external)
      log "Image status: external (${DCTL_INIT_IMAGE_REF})"
      ;;
    no-image)
      log "Image status: no image declared"
      ;;
  esac
  log "Generated config: $deployed_config"
  log "Registry path: ${DCTL_CONFIG_DIR}/projects.yaml"
  log "Smoke test: $test_status"

  [[ $test_status == "passed" ]] || return 1
}

main_init() {
  cmd_init "$@"
}
