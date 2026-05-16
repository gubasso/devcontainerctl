# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_INIT_GENERATE_CACHE_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_INIT_GENERATE_CACHE_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require _lib/json/strip_comments.sh
__dctl_require _lib/json/validate_layer.sh
__dctl_require _lib/json/merge_runargs.sh
__dctl_require _lib/json/merge_configs.sh
__dctl_require _lib/registry/validate_manifest.sh
__dctl_require _lib/registry/read_manifest_layers.sh
__dctl_require commands/net/_default_allowlist.sh
__dctl_require commands/net/_user_allowlist.sh
__dctl_require commands/net/_compose.sh
__dctl_require commands/image/build.sh
__dctl_require commands/image/_helpers.sh
__dctl_require runtime/common.sh
__dctl_require runtime/krun.sh

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
  local tmp_path tmp_acc allowlist_json
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
  # The cache file is shared across workspaces (keyed only by manifest name in
  # $DCTL_DEVCONTAINER_CACHE_DIR), so it must not capture per-workspace git
  # remotes. Runtime injection in krun.sh:_krun_inject_allowlist_env recomputes
  # the full per-workspace list at `podman run` time.
  allowlist_json="$(DCTL_NET_OMIT_GIT_REMOTES=1 DCTL_NET_MANIFEST_HINT="$template" net_compose_allowlist_json "$WORKSPACE_FOLDER")"
  if ! jq --argjson allow "$allowlist_json" '
    .network = ((.network // {}) | .allow = $allow)
  ' "$tmp_path" >"${tmp_path}.allow"; then
    rm -f "$tmp_path" "${tmp_path}.allow"
    err "Failed to merge allowlist into cache for '$template'"
  fi
  mv "${tmp_path}.allow" "$tmp_path"
  # TODO(70): honor manifest runtime.resources block when schema support lands.
  if ! jq '
    .runArgs = (
      (.runArgs // []) as $args
      | if ($args | index("--runtime")) then $args
        else $args + ["--runtime", "krun"] end
    )
  ' "$tmp_path" >"${tmp_path}.overlay"; then
    rm -f "$tmp_path" "${tmp_path}.overlay"
    err "Failed to append runtime overlay for '$template'"
  fi
  mv "${tmp_path}.overlay" "$tmp_path"
  mv "$tmp_path" "$cached_path"
  printf '%s\n' "$cached_path"
  printf 'generated\n'
}

# shellcheck disable=SC2034
# DCTL_INIT_IMAGE_{STATUS,REF} are consumed by commands/init/do.sh after this
# function returns; shellcheck cannot see the cross-file read site.
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

  if rt_image_inspect "$image_ref"; then
    DCTL_INIT_IMAGE_STATUS="already-built"
    return 0
  fi

  cmd_image_build "$image_name"
  DCTL_INIT_IMAGE_STATUS="built-now"
}
