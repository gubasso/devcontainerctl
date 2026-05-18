# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_INIT_DO_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_INIT_DO_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require _lib/fzf.sh
__dctl_require _lib/json/strip_comments.sh
__dctl_require _lib/json/validate_layer.sh
__dctl_require _lib/json/merge_runargs.sh
__dctl_require _lib/json/merge_configs.sh
__dctl_require _lib/registry/file.sh
__dctl_require _lib/registry/exists.sh
__dctl_require _lib/registry/validate_manifest.sh
__dctl_require _lib/registry/validate.sh
__dctl_require _lib/registry/read_manifest_layers.sh
__dctl_require _lib/registry/read_field.sh
__dctl_require _lib/registry/lookup_manifest.sh
__dctl_require _lib/registry/lookup_discovery.sh
__dctl_require _lib/registry/ensure_file.sh
__dctl_require _lib/registry/has_project.sh
__dctl_require _lib/registry/register_project_defaults.sh
__dctl_require commands/init/_select_interactive.sh
__dctl_require commands/init/_generate_cache.sh

cmd_init_do() {
  local devcontainer=""
  local force=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --devcontainer)
        [[ $# -ge 2 ]] || err "--devcontainer requires a value"
        devcontainer="$2"
        shift 2
        ;;
      --force)
        force=true
        shift
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

  local canonical_name existing_manifest registry_force=false
  canonical_name="$(resolve_canonical_project_name)"

  # Skip the validating registry lookup when --force is set: the lookup runs
  # _validate_registry, which would reject a legacy `devcontainer:` key and
  # exit before register_project_defaults could scrub it. The "Switching"
  # warning only fires on the non-force branch, so the lookup is only needed
  # there.
  if [[ $force == true ]]; then
    registry_force=true
    existing_manifest=""
  else
    if command -v yq >/dev/null 2>&1; then
      existing_manifest="$(_registry_lookup_devcontainer_manifest "$canonical_name")"
    else
      existing_manifest=""
    fi
    if [[ -n $existing_manifest && $existing_manifest != "$devcontainer" ]]; then
      warn "Switching project '$canonical_name' from manifest '$existing_manifest' to '$devcontainer'"
      registry_force=true
    fi
  fi

  local cache_output deployed_config config_status
  cache_output="$(generate_cached_devcontainer "$devcontainer" "$force")" || return $?
  deployed_config="$(head -1 <<<"$cache_output")"
  config_status="$(tail -1 <<<"$cache_output")"

  ensure_image_available_for_devcontainer "$devcontainer"

  register_project_defaults "$canonical_name" "$devcontainer" "$registry_force"

  local test_status="passed"
  if ! DCTL_CLI_CONFIG="$deployed_config" cmd_test_run; then
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
  log "Cache path: $deployed_config"
  log "Cache status: $config_status"
  log "Registry path: ${DCTL_CONFIG_DIR}/projects.yaml"
  log "Smoke test: $test_status"

  [[ $test_status == "passed" ]] || return 1
}
