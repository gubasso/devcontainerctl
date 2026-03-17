# shellcheck shell=bash
# Auth token extraction for dctl (sourced, not executed directly)

[[ -n "${_DCTL_AUTH_LOADED:-}" ]] && return 0
readonly _DCTL_AUTH_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/common.sh"

_extract_gh_token() {
  if ! command -v gh >/dev/null 2>&1; then
    warn "gh CLI not found — install from https://cli.github.com"
    return 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    warn "gh not authenticated — run 'gh auth login' on the host"
    return 1
  fi
  local token
  token=$(gh auth token 2>/dev/null)
  if [[ -z "$token" ]]; then
    warn "Failed to extract gh token"
    return 1
  fi
  printf '%s' "$token"
}

_extract_glab_token() {
  if ! command -v glab >/dev/null 2>&1; then
    warn "glab CLI not found — install from https://gitlab.com/gitlab-org/cli"
    return 1
  fi
  if ! glab auth status >/dev/null 2>&1; then
    warn "glab not authenticated — run 'glab auth login' on the host"
    return 1
  fi
  local token
  token=$(glab auth status --show-token 2>&1 | awk '/Token:/{print $NF}')
  if [[ -z "$token" ]]; then
    warn "Failed to extract glab token"
    return 1
  fi
  printf '%s' "$token"
}

_TOKEN_ENV_FILE="${_TOKEN_ENV_FILE:-/tmp/.devcontainer-tokens.env}"

cmd_auth_init_tokens() {
  local env_file="$_TOKEN_ENV_FILE"
  local gh_ok=false glab_ok=false

  umask 077
  : >"$env_file"

  local token
  if token=$(_extract_gh_token); then
    printf 'GH_TOKEN=%s\n' "$token" >>"$env_file"
    log "GitHub token extracted"
    gh_ok=true
  else
    printf 'GH_TOKEN=\n' >>"$env_file"
  fi

  if token=$(_extract_glab_token); then
    printf 'GITLAB_TOKEN=%s\n' "$token" >>"$env_file"
    log "GitLab token extracted"
    glab_ok=true
  else
    printf 'GITLAB_TOKEN=\n' >>"$env_file"
  fi

  if [[ "$gh_ok" == false && "$glab_ok" == false ]]; then
    warn "No tokens extracted — gh/glab auth will not work in container"
  fi

  log "Token env file written to ${env_file}"
  return 0
}

usage_auth() {
  cat <<'EOF'
Usage: dctl auth <command>

Commands:
  init-tokens  Extract gh/glab auth tokens into an env file for container use
  help         Show this help text
EOF
}

main_auth() {
  local cmd="${1:-help}"
  case "$cmd" in
    init-tokens)
      shift
      cmd_auth_init_tokens "$@"
      ;;
    help | -h | --help)
      usage_auth
      ;;
    *)
      err "Unknown auth command: $cmd"
      ;;
  esac
}
