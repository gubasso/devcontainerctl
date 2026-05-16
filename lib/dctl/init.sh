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
  --force                              Rebuild cached merged config and re-register
  --help, -h                           Show this help text

Examples:
  dctl init --devcontainer python
  dctl init --force --devcontainer rust
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

_strip_jsonc_comments() {
  sed '/^[[:space:]]*\/\//d' "$1"
}

_validate_devcontainer_layer() {
  local layer_path="$1"
  local layer_json="$2"
  local key runtime_value
  # Allowlist tracks the Microsoft devcontainer.json schema (general dev
  # container properties + non-compose properties) plus dctl's `runtime` key.
  # See https://containers.dev/implementors/json_reference/ — keys present in
  # spec-conformant configs must not error here even when dctl ignores them at
  # runtime.
  local -A allowed_keys=(
    [name]=1
    [image]=1
    [build]=1
    [entrypoint]=1
    [secrets]=1
    [workspaceFolder]=1
    [workspaceMount]=1
    [mounts]=1
    [runArgs]=1
    [containerEnv]=1
    [remoteEnv]=1
    [remoteUser]=1
    [containerUser]=1
    [updateRemoteUserUID]=1
    [containerName]=1
    [waitFor]=1
    [postCreateCommand]=1
    [postStartCommand]=1
    [postAttachCommand]=1
    [initializeCommand]=1
    [onCreateCommand]=1
    [updateContentCommand]=1
    [shutdownAction]=1
    [features]=1
    [overrideFeatureInstallOrder]=1
    [customizations]=1
    [forwardPorts]=1
    [portsAttributes]=1
    [otherPortsAttributes]=1
    [appPort]=1
    [hostRequirements]=1
    [capAdd]=1
    [securityOpt]=1
    [privileged]=1
    [init]=1
    [overrideCommand]=1
    [userEnvProbe]=1
    [runtime]=1
  )
  # Add the JSON Schema marker key separately: shfmt rewrites a
  # double-quoted key inside the array literal back to single quotes,
  # which then triggers shellcheck SC2016.
  # shellcheck disable=SC2016
  allowed_keys['$schema']=1

  while IFS= read -r key; do
    [[ -n $key ]] || continue
    if [[ -z ${allowed_keys[$key]:-} ]]; then
      printf 'Unsupported devcontainer.json key: %s (layer: %s)\n' "$key" "$layer_path" >&2
      return 1
    fi
  done < <(jq -r 'keys[]' <<<"$layer_json")

  runtime_value="$(jq -r '.runtime // empty' <<<"$layer_json")"
  if [[ -n $runtime_value && $runtime_value != "krun" ]]; then
    printf 'Unsupported devcontainer.json key: runtime=%s (layer: %s)\n' "$runtime_value" "$layer_path" >&2
    return 1
  fi
}

_merge_runargs_json() {
  local base_json="$1"
  local tmpl_json="$2"
  local -a items ordered_ids
  local -A keyed_flags seen_ids id_flag id_value
  local idx flag value identity

  # Quote the keys so shfmt does not insert spaces around the dashes inside
  # the bracket subscripts (which produces literal "--cgroup - parent" keys).
  keyed_flags=(
    ["--name"]=1
    ["--hostname"]=1
    ["--label"]=1
    ["--user"]=1
    ["--workdir"]=1
    ["--network"]=1
    ["--ipc"]=1
    ["--pid"]=1
    ["--uts"]=1
    ["--cgroup-parent"]=1
    ["--memory"]=1
    ["--cpus"]=1
    ["--cpuset-cpus"]=1
    ["--cpuset-mems"]=1
  )

  mapfile -t items < <(
    jq -sr '((.[0].runArgs // []) + (.[1].runArgs // []))[]' \
      <(printf '%s\n' "$base_json") \
      <(printf '%s\n' "$tmpl_json")
  )

  if ((${#items[@]} % 2 != 0)); then
    printf 'runArgs must contain flag/value pairs; got odd-length array (%d entries)\n' "${#items[@]}" >&2
    return 1
  fi

  ordered_ids=()
  for ((idx = 0; idx < ${#items[@]}; idx += 2)); do
    flag="${items[idx]}"
    value="${items[idx + 1]}"

    if [[ -n ${keyed_flags[$flag]:-} ]]; then
      identity="keyed:${flag}"
      if [[ -z ${seen_ids[$identity]:-} ]]; then
        ordered_ids+=("$identity")
        seen_ids[$identity]=1
      fi
      id_flag[$identity]="$flag"
      id_value[$identity]="$value"
      continue
    fi

    identity="pair:${flag}"$'\x1f'"$value"
    if [[ -n ${seen_ids[$identity]:-} ]]; then
      continue
    fi
    ordered_ids+=("$identity")
    seen_ids[$identity]=1
    id_flag[$identity]="$flag"
    id_value[$identity]="$value"
  done

  {
    printf '['
    for idx in "${!ordered_ids[@]}"; do
      identity="${ordered_ids[$idx]}"
      ((idx > 0)) && printf ','
      printf '%s\n' "${id_flag[$identity]}" | jq -R .
      printf ','
      printf '%s\n' "${id_value[$identity]}" | jq -R .
    done
    printf ']'
  }
}

merge_two_configs() {
  local base_path="$1"
  local template_path="$2"

  local base_json tmpl_json jq_err runargs_json

  base_json="$(_strip_jsonc_comments "$base_path")" || return 1
  tmpl_json="$(_strip_jsonc_comments "$template_path")" || return 1

  if ! jq_err="$(jq empty <<<"$base_json" 2>&1)"; then
    printf 'JSON syntax error in %s:\n  %s\n' "$base_path" "$jq_err" >&2
    return 1
  fi
  if ! jq_err="$(jq empty <<<"$tmpl_json" 2>&1)"; then
    printf 'JSON syntax error in %s:\n  %s\n' "$template_path" "$jq_err" >&2
    return 1
  fi

  _validate_devcontainer_layer "$base_path" "$base_json" || return 1
  _validate_devcontainer_layer "$template_path" "$tmpl_json" || return 1

  runargs_json="$(_merge_runargs_json "$base_json" "$tmpl_json")" || return 1

  jq -n \
    --argjson base "$base_json" \
    --argjson tmpl "$tmpl_json" \
    --argjson runargs "$runargs_json" '
      $base as $base |
      $tmpl as $tmpl |
      ($base * $tmpl) |
      .mounts = (($base.mounts // []) + ($tmpl.mounts // [])) |
      .postCreateCommand =
        if (($base.postCreateCommand // null) | type) == "object"
          and (($tmpl.postCreateCommand // null) | type) == "object"
        then (($base.postCreateCommand // {}) * ($tmpl.postCreateCommand // {}))
        else ($tmpl.postCreateCommand // $base.postCreateCommand)
        end |
      .containerEnv = (($base.containerEnv // {}) * ($tmpl.containerEnv // {})) |
      .remoteEnv = (($base.remoteEnv // {}) * ($tmpl.remoteEnv // {})) |
      .runArgs = $runargs |
      if $tmpl.workspaceMount != null then .workspaceMount = $tmpl.workspaceMount else . end |
      if $tmpl.workspaceFolder != null then .workspaceFolder = $tmpl.workspaceFolder else . end
    '
}

discover_config_layers() {
  local config_name="$1"
  local manifest
  manifest="$(config_compose_manifest_path "$config_name")"

  [[ -f $manifest ]] || err "No manifest found for '$config_name' at $manifest"
  _validate_compose_manifest "$manifest"

  local -a layers=()
  local layer_name layer_path
  while IFS= read -r layer_name; do
    [[ -n $layer_name ]] || continue
    layer_path="${DCTL_DEVCONTAINER_DIR}/${layer_name}/devcontainer.json"
    [[ -f $layer_path ]] || err "Layer '$layer_name' referenced in manifest '$config_name' not found: $layer_path"
    layers+=("$layer_path")
  done < <(_read_manifest_layers "$manifest")

  [[ ${#layers[@]} -gt 0 ]] || err "No layers found in manifest for '$config_name'"
  printf '%s\n' "${layers[@]}"
}

cache_is_fresh() {
  local cached_path="$1"
  shift
  [[ -f $cached_path ]] || return 1
  local source_path
  for source_path in "$@"; do
    [[ $cached_path -nt $source_path ]] || return 1
  done
}

_validate_deployed_devcontainer() {
  local template="$1"
  local manifest
  manifest="$(config_compose_manifest_path "$template")"
  [[ -f $manifest ]] || err "Unknown deployed devcontainer: $template (no manifest at $manifest)"
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

generate_cached_devcontainer() {
  local template="$1"
  local force="${2:-false}"

  _validate_deployed_devcontainer "$template"

  local manifest cached_path
  manifest="$(config_compose_manifest_path "$template")"
  cached_path="$(devcontainer_cache_path_for_manifest "$template")"

  local -a config_layers=()
  mapfile -t config_layers < <(discover_config_layers "$template")
  if [[ ${#config_layers[@]} -eq 0 ]]; then
    err "No composable config layers found for ${template}. Run: dctl deploy devcontainer ${template}"
  fi

  if [[ $force != true ]] && cache_is_fresh "$cached_path" "$manifest" "${config_layers[@]}"; then
    printf '%s\n' "$cached_path"
    printf 'cached\n'
    return 0
  fi

  # jq is only needed for the merge path; a fresh cache short-circuits
  # above so callers (e.g. `dctl ws reup`) can reuse a cached config
  # without requiring jq to be installed.
  require_cmd jq

  mkdir -p "$(dirname "$cached_path")"
  local tmp_path tmp_acc
  tmp_path="$(mktemp "${cached_path}.tmp.XXXXXX")"
  tmp_acc="$(mktemp "${cached_path}.layers.XXXXXX")"
  cp "${config_layers[0]}" "$tmp_acc"

  local layer_path tmp_next
  for layer_path in "${config_layers[@]:1}"; do
    tmp_next="$(mktemp "${cached_path}.layers.XXXXXX")"
    if ! merge_two_configs "$tmp_acc" "$layer_path" >"$tmp_next"; then
      rm -f "$tmp_path" "$tmp_acc" "$tmp_next"
      err "Failed to merge layer '$layer_path' for '$template'"
    fi
    rm -f "$tmp_acc"
    tmp_acc="$tmp_next"
  done

  mv "$tmp_acc" "$tmp_path"
  mv "$tmp_path" "$cached_path"
  printf '%s\n' "$cached_path"
  printf 'generated\n'
}

ensure_image_available_for_devcontainer() {
  local devcontainer_name="$1"
  local config_path cached_path image_ref image_name

  DCTL_INIT_IMAGE_STATUS=""
  DCTL_INIT_IMAGE_REF=""

  cached_path="$(devcontainer_cache_path_for_manifest "$devcontainer_name")"
  config_path="$(config_devcontainer_path "$devcontainer_name")"
  if [[ -f $cached_path ]]; then
    image_ref="$(_infer_image_from_devcontainer_json "$cached_path" || true)"
  else
    image_ref="$(_infer_image_from_devcontainer_json "$config_path" || true)"
  fi

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
  log "Cache path: $deployed_config"
  log "Cache status: $config_status"
  log "Registry path: ${DCTL_CONFIG_DIR}/projects.yaml"
  log "Smoke test: $test_status"

  [[ $test_status == "passed" ]] || return 1
}

main_init() {
  cmd_init "$@"
}
