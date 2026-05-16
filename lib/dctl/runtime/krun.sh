# shellcheck shell=bash
# Podman + crun-krun runtime backend (sourced, not executed directly)

[[ -n ${_DCTL_RUNTIME_KRUN_LOADED:-} ]] && return 0
readonly _DCTL_RUNTIME_KRUN_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require _lib/auth/gh_token.sh
__dctl_require _lib/auth/glab_token.sh
__dctl_require _lib/workspace/label_filter.sh
__dctl_require commands/doctor/_helpers.sh
__dctl_require commands/doctor/kvm.sh
# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/runtime/common.sh"

_dctl_krun_preflight() {
  if [[ -n ${_DCTL_KRUN_PREFLIGHT_OK:-} ]]; then
    return 0
  fi

  if ! _doctor_minimal_preflight; then
    err "krun runtime preflight failed. Run 'dctl doctor' for full diagnostics."
  fi

  _DCTL_KRUN_PREFLIGHT_OK=1
}

_krun_strip_jsonc_comments() {
  sed '/^[[:space:]]*\/\//d' "$1"
}

_krun_resolve_config() {
  local workspace_folder="$1"
  local config_path="$2"
  local config_json jq_err

  [[ -n $workspace_folder ]] || err "rt_* requires a workspace folder"
  [[ -n $config_path ]] || err "rt_* requires a config path"
  [[ -f $config_path ]] || err "Resolved devcontainer config does not exist: $config_path"

  config_json="$(_krun_strip_jsonc_comments "$config_path")" || return 1
  if ! jq_err="$(jq empty <<<"$config_json" 2>&1)"; then
    printf 'JSON syntax error in %s:\n  %s\n' "$config_path" "$jq_err" >&2
    return 1
  fi

  printf '%s\n' "$config_json"
}

_krun_workspace_label_filter() {
  local workspace_folder="$1"
  [[ -n $workspace_folder ]] || err "_krun_workspace_label_filter requires a workspace folder"
  printf 'label=devcontainer.local_folder=%s' "$(cd -- "$workspace_folder" && pwd -P)"
}

_krun_default_annotations() {
  printf '%s\0' \
    "--annotation" "krun.ram_mib=4096" \
    "--annotation" "krun.cpus=2"
}

_krun_http2_workaround() {
  # The referenced ai-agents-sandbox lines currently fall back to no-microvm for
  # Copilot CLI rather than applying an env/sysctl tweak. Keep a documented hook
  # here so the Phase 10 backend can grow a real workaround once there is a
  # runtime-scoped setting to port.
  if [[ -n ${DCTL_KRUN_HTTP2_WORKAROUND:-} ]]; then
    :
  fi
}

_krun_emit_mount_flag() {
  local mount_json="$1"
  local mount_type source target options readonly_flag

  if jq -e 'type == "string"' >/dev/null 2>&1 <<<"$mount_json"; then
    printf '%s\0%s\0' "--mount" "$(jq -r '.' <<<"$mount_json")"
    return 0
  fi

  mount_type="$(jq -r '.type // empty' <<<"$mount_json")"
  source="$(jq -r '.source // .src // empty' <<<"$mount_json")"
  target="$(jq -r '.target // .dst // .destination // empty' <<<"$mount_json")"
  # `.consistency` is a Docker-Desktop-on-macOS metadata field and is silently
  # dropped; Podman's `--mount` does not accept it (would surface as a parse
  # error). Track for parity in DECISION-LINUX.md when relevant.
  options=""
  readonly_flag="$(jq -r '.readonly // .readOnly // empty' <<<"$mount_json")"

  [[ -n $mount_type ]] || err "Mount entry is missing .type"
  [[ -n $target ]] || err "Mount entry is missing .target"

  local spec="type=${mount_type},target=${target}"
  if [[ -n $source ]]; then
    spec="${spec},source=${source}"
  fi
  if [[ -n $options ]]; then
    spec="${spec},${options}"
  fi
  if [[ $readonly_flag == "true" ]]; then
    spec="${spec},readonly"
  fi

  printf '%s\0%s\0' "--mount" "$spec"
}

_krun_extract_run_flags() {
  local config_json="$1"
  local item key value

  while IFS= read -r item; do
    printf '%s\0' "$item"
  done < <(jq -r '.runArgs // [] | .[]' <<<"$config_json")

  while IFS= read -r key; do
    value="$(jq -r --arg key "$key" '.containerEnv[$key]' <<<"$config_json")"
    printf '%s\0%s=%s\0' "--env" "$key" "$value"
  done < <(jq -r '.containerEnv // {} | keys[]' <<<"$config_json")

  while IFS= read -r item; do
    _krun_emit_mount_flag "$item"
  done < <(jq -c '.mounts // [] | .[]' <<<"$config_json")

  value="$(jq -r '.workspaceMount // empty' <<<"$config_json")"
  if [[ -n $value ]]; then
    printf '%s\0%s\0' "--mount" "$value"
  fi
}

_krun_get_image_tag() {
  printf 'devimg/%s:latest\n' "$1"
}

_krun_build_context_dir() {
  local image_name="$1"
  local config_path="$2"
  local config_json="$3"
  local context_dir config_dir build_context

  config_dir="$(dirname "$config_path")"
  build_context="$(jq -r '.build.context // empty' <<<"$config_json")"
  if [[ -n $build_context ]]; then
    if [[ $build_context == /* ]]; then
      printf '%s\n' "$build_context"
    else
      printf '%s\n' "$(cd -- "$config_dir" && cd -- "$build_context" && pwd -P)"
    fi
    return 0
  fi

  if [[ -n $image_name ]]; then
    context_dir="$(dirname "$(config_image_path "$image_name")")"
    if [[ -d $context_dir ]]; then
      printf '%s\n' "$context_dir"
      return 0
    fi
  fi

  printf '%s\n' "$config_dir"
}

_krun_build_dockerfile_path() {
  local context_dir="$1"
  local config_path="$2"
  local config_json="$3"
  local dockerfile config_dir resolved

  dockerfile="$(jq -r '.build.dockerfile // empty' <<<"$config_json")"
  [[ -n $dockerfile ]] || return 0

  if [[ $dockerfile == /* ]]; then
    printf '%s\n' "$dockerfile"
    return 0
  fi

  # Per the Dev Container spec, `build.dockerfile` is relative to the
  # devcontainer.json file (not the build context). Resolve against
  # config_dir first; fall back to context_dir for layouts that store the
  # Dockerfile alongside the build context (dctl `images/<name>/`).
  config_dir="$(dirname "$config_path")"
  resolved="${config_dir}/${dockerfile}"
  if [[ -f $resolved ]]; then
    printf '%s\n' "$resolved"
    return 0
  fi

  if [[ -f "${context_dir}/${dockerfile}" ]]; then
    printf '%s\n' "${context_dir}/${dockerfile}"
    return 0
  fi

  # Fall back to the spec-correct (config_dir) path; podman build will
  # surface a clear error if the file is missing.
  printf '%s\n' "$resolved"
}

_krun_build_image_name() {
  local config_path="$1"
  local config_json="$2"
  local image_name dockerfile_path

  image_name="$(basename "$(dirname "$config_path")")"
  dockerfile_path="$(jq -r '.build.dockerfile // empty' <<<"$config_json")"
  if [[ -n $dockerfile_path ]]; then
    dockerfile_path="$(basename "$dockerfile_path")"
    dockerfile_path="${dockerfile_path%.*}"
    if [[ -n $dockerfile_path && $dockerfile_path != "Dockerfile" && $dockerfile_path != "Containerfile" ]]; then
      image_name="$dockerfile_path"
    fi
  fi

  printf '%s\n' "$image_name"
}

_krun_collect_exec_env_flags() {
  local config_json="$1"
  local key value

  while IFS= read -r key; do
    value="$(jq -r --arg key "$key" '.remoteEnv[$key]' <<<"$config_json")"
    printf '%s\0%s=%s\0' "--env" "$key" "$value"
  done < <(jq -r '.remoteEnv // {} | keys[]' <<<"$config_json")

  for key in TERM COLORTERM; do
    if [[ -n ${!key:-} ]]; then
      printf '%s\0%s=%s\0' "--env" "$key" "${!key}"
    fi
  done

  if value="$(_extract_gh_token 2>/dev/null)"; then
    printf '%s\0%s=%s\0' "--env" "GH_TOKEN" "$value"
  fi
  if value="$(_extract_glab_token 2>/dev/null)"; then
    printf '%s\0%s=%s\0' "--env" "GITLAB_TOKEN" "$value"
  fi
}

_krun_rt_run() {
  local workspace_folder="$1"
  local config_path="$2"
  shift 2

  _dctl_krun_preflight

  local config_json image image_name context_dir ctr
  local -a flags annotations extra_args run_cmd

  config_json="$(_krun_resolve_config "$workspace_folder" "$config_path")" || return 1

  flags=()
  while IFS= read -r -d '' item; do
    flags+=("$item")
  done < <(_krun_extract_run_flags "$config_json")

  annotations=()
  while IFS= read -r -d '' item; do
    annotations+=("$item")
  done < <(_krun_default_annotations)

  extra_args=("$@")

  image="$(jq -r '.image // empty' <<<"$config_json")"
  local build_dockerfile=""
  local -a build_dockerfile_args
  if [[ -z $image ]]; then
    if [[ $(jq -r 'has("build")' <<<"$config_json") == "true" ]]; then
      image_name="$(_krun_build_image_name "$config_path" "$config_json")"
      context_dir="$(_krun_build_context_dir "$image_name" "$config_path" "$config_json")"
      build_dockerfile="$(_krun_build_dockerfile_path "$context_dir" "$config_path" "$config_json")"
      build_dockerfile_args=()
      [[ -n $build_dockerfile ]] && build_dockerfile_args=(--dockerfile "$build_dockerfile")
      _krun_rt_build "$image_name" "$context_dir" "${build_dockerfile_args[@]}"
      image="$(_krun_get_image_tag "$image_name")"
    else
      err "Resolved devcontainer config has neither .image nor .build: $config_path"
    fi
  fi

  if ! _krun_rt_image_inspect "$image"; then
    if [[ $(jq -r 'has("build")' <<<"$config_json") == "true" ]]; then
      image_name="$(_krun_build_image_name "$config_path" "$config_json")"
      context_dir="$(_krun_build_context_dir "$image_name" "$config_path" "$config_json")"
      build_dockerfile="$(_krun_build_dockerfile_path "$context_dir" "$config_path" "$config_json")"
      build_dockerfile_args=()
      [[ -n $build_dockerfile ]] && build_dockerfile_args=(--dockerfile "$build_dockerfile")
      _krun_rt_build "$image_name" "$context_dir" "${build_dockerfile_args[@]}"
      image="$(_krun_get_image_tag "$image_name")"
    else
      err "Image not found locally and no build block is available: $image"
    fi
  fi

  _krun_http2_workaround

  run_cmd=(
    podman run
    --runtime krun
    --detach
    --label "devcontainer.local_folder=$(cd -- "$workspace_folder" && pwd -P)"
  )
  run_cmd+=("${annotations[@]}")
  run_cmd+=("${flags[@]}")
  run_cmd+=("${extra_args[@]}")
  run_cmd+=("$image")

  ctr="$("${run_cmd[@]}")" || return 1

  if ! declare -F run_postcreate >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "${DCTL_LIB_DIR}/lifecycle.sh"
  fi
  run_postcreate "$ctr" "$config_json"
  run_poststart "$ctr" "$config_json"

  printf '%s\n' "$ctr"
}

_krun_rt_exec() {
  local workspace_folder="$1"
  local config_path="$2"
  shift 2

  _dctl_krun_preflight

  local config_json ctr arg value
  local -a config_env_flags exec_env_flags user_env_flags cmd tty_flag

  config_json="$(_krun_resolve_config "$workspace_folder" "$config_path")" || return 1

  user_env_flags=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env)
        [[ $# -ge 2 ]] || err "rt_exec --env requires K=V"
        user_env_flags+=(--env "$2")
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *)
        err "rt_exec expected [--env K=V ...] -- <cmd...>"
        ;;
    esac
  done

  [[ $# -gt 0 ]] || err "rt_exec requires a command after --"
  cmd=("$@")

  ctr="$(_krun_rt_ps --quiet "$workspace_folder" | head -n1)"
  [[ -n $ctr ]] || err "No workspace container found for $workspace_folder"

  config_env_flags=()
  while IFS= read -r -d '' arg; do
    config_env_flags+=("$arg")
  done < <(_krun_collect_exec_env_flags "$config_json")

  exec_env_flags=("${config_env_flags[@]}" "${user_env_flags[@]}")
  tty_flag=()
  if [[ -t 0 ]]; then
    tty_flag=(-it)
  fi

  podman exec "${tty_flag[@]}" "${exec_env_flags[@]}" "$ctr" "${cmd[@]}"
}

_krun_rt_ps() {
  # ps/rm only need `podman` (no KVM); gate so callers get the standard diagnostic.
  require_cmd podman

  local quiet=false
  local running=false
  local format_template=""
  local workspace_folder
  local -a cmd

  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      --quiet)
        quiet=true
        shift
        ;;
      --format)
        [[ $# -ge 2 ]] || err "rt_ps --format requires a template"
        format_template="$2"
        shift 2
        ;;
      --running)
        running=true
        shift
        ;;
      --)
        shift
        break
        ;;
      *)
        break
        ;;
    esac
  done

  workspace_folder="${1:-}"
  [[ -n $workspace_folder ]] || err "rt_ps requires a workspace folder"
  [[ $quiet == false || -z $format_template ]] || err "rt_ps --quiet and --format are mutually exclusive"

  cmd=(podman ps --filter "$(_krun_workspace_label_filter "$workspace_folder")")
  if [[ $running != true ]]; then
    cmd+=(-a)
  fi
  if [[ $quiet == true ]]; then
    cmd+=(-q)
  elif [[ -n $format_template ]]; then
    cmd+=(--format "$format_template")
  else
    cmd+=(--format '{{.ID}}')
  fi

  "${cmd[@]}"
}

_krun_rt_rm() {
  local workspace_folder="$1"
  local ids

  ids="$(_krun_rt_ps --quiet "$workspace_folder")"
  [[ -n $ids ]] || return 0

  xargs -r podman rm -f <<<"$ids"
}

_krun_rt_build() {
  local image_name="$1"
  local context_dir="$2"
  shift 2

  # build does not need KVM/libkrun (no microvm); full preflight stays on rt_run/rt_exec.
  require_cmd podman

  # Optional leading `--dockerfile <path>` lets internal callers pass a
  # pre-resolved Dockerfile without colliding with the public
  # `rt_build <image_name> <context_dir> [--build-arg K=V ...]` contract,
  # which only documents `--build-arg` style flags after the context.
  local dockerfile_arg=""
  if [[ ${1:-} == "--dockerfile" ]]; then
    [[ $# -ge 2 ]] || err "rt_build --dockerfile requires a path"
    dockerfile_arg="$2"
    shift 2
  fi

  local tag secret_file dockerfile_path token
  local -a secret_args build_cmd

  tag="$(_krun_get_image_tag "$image_name")"
  secret_args=()
  secret_file=""

  if token="$(_extract_gh_token 2>/dev/null)"; then
    secret_file="$(mktemp)"
    printf '%s' "$token" >"$secret_file"
    secret_args=(--secret "id=gh_token,src=${secret_file}")
  fi

  dockerfile_path=""
  if [[ -n $dockerfile_arg ]]; then
    dockerfile_path="$dockerfile_arg"
  elif [[ -f "${context_dir}/Containerfile" ]]; then
    dockerfile_path="${context_dir}/Containerfile"
  elif [[ -f "${context_dir}/Dockerfile" ]]; then
    dockerfile_path="${context_dir}/Dockerfile"
  fi

  build_cmd=(podman build --tag "$tag")
  if [[ -n $dockerfile_path ]]; then
    build_cmd+=(--file "$dockerfile_path")
  fi
  build_cmd+=("${secret_args[@]}")
  build_cmd+=("$@")
  build_cmd+=("$context_dir")

  "${build_cmd[@]}"
  local status=$?

  if [[ -n $secret_file ]]; then
    rm -f "$secret_file"
  fi

  return "$status"
}

_krun_rt_image_inspect() {
  require_cmd podman
  podman image inspect "$1" >/dev/null 2>&1
}
