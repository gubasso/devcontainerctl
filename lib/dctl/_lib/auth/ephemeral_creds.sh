# shellcheck shell=bash

[[ -n ${_DCTL_LIB_AUTH_EPHEMERAL_CREDS_LOADED:-} ]] && return 0
readonly _DCTL_LIB_AUTH_EPHEMERAL_CREDS_LOADED=1

__dctl_require _lib/workspace/session_hash.sh

collect_ephemeral_cred_mounts() {
  local -n _out="$1"
  _out=()

  local session_dir home_dir
  session_dir="$(workspace_session_dir)" || return 1
  home_dir="${HOME:?HOME must be set}"

  mkdir -p "$session_dir"
  chmod 0700 "$session_dir"

  _collect_claude_cred_mounts _out "$session_dir" "$home_dir"
  _collect_codex_cred_mounts _out "$session_dir" "$home_dir"
  _collect_gemini_cred_mounts _out "$session_dir" "$home_dir"
}

_copy_ephemeral_cred_file() {
  local source_path="$1"
  local dest_path="$2"
  local target_path="$3"
  local -n _cred_mounts="$4"

  [[ -f $source_path ]] || return 1

  mkdir -p "$(dirname "$dest_path")"
  cp "$source_path" "$dest_path"
  chmod 0700 "$(dirname "$dest_path")"
  chmod 0600 "$dest_path"
  _cred_mounts+=(--mount "type=bind,source=${dest_path},target=${target_path},readonly")
}

_collect_claude_cred_mounts() {
  local -n _mounts="$1"
  local session_dir="$2"
  local home_dir="$3"

  local -a sources=(
    "${home_dir}/.claude/.credentials.json"
    "${home_dir}/.claude/credentials.json"
    "${home_dir}/.claude.json"
  )
  local source_path rel_path target_path
  for source_path in "${sources[@]}"; do
    case "$source_path" in
      "${home_dir}/.claude/"*)
        rel_path="claude/${source_path#"${home_dir}/.claude/"}"
        target_path="${home_dir}/.claude/${source_path#"${home_dir}/.claude/"}"
        ;;
      "${home_dir}/.claude.json")
        rel_path="claude.json"
        target_path="${home_dir}/.claude.json"
        ;;
      *)
        continue
        ;;
    esac
    if _copy_ephemeral_cred_file \
      "$source_path" \
      "${session_dir}/${rel_path}" \
      "$target_path" \
      _mounts; then
      return 0
    fi
  done
}

_collect_codex_cred_mounts() {
  local -n _mounts="$1"
  local session_dir="$2"
  local home_dir="$3"

  _copy_ephemeral_cred_file \
    "${home_dir}/.codex/auth.json" \
    "${session_dir}/codex/auth.json" \
    "${home_dir}/.codex/auth.json" \
    _mounts || true
}

_collect_gemini_cred_mounts() {
  local -n _mounts="$1"
  local session_dir="$2"
  local home_dir="$3"

  local -a sources=(
    "${home_dir}/.gemini/key.json"
    "${home_dir}/.gemini/oauth_creds.json"
  )
  local source_path rel_name
  for source_path in "${sources[@]}"; do
    rel_name="$(basename "$source_path")"
    _copy_ephemeral_cred_file \
      "$source_path" \
      "${session_dir}/gemini/${rel_name}" \
      "${home_dir}/.gemini/${rel_name}" \
      _mounts || true
  done
}
