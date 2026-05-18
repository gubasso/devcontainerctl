# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_NET_DEFAULT_ALLOWLIST_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_NET_DEFAULT_ALLOWLIST_LOADED=1

net_default_allowlist() {
  local -a defaults=(
    api.anthropic.com
    api.openai.com
    "*.googleapis.com"
    registry.npmjs.org
    pypi.org
    files.pythonhosted.org
    crates.io
    index.crates.io
    download.opensuse.org
    github.com
    "*.githubusercontent.com"
    gitlab.com
    "*.gitlab.io"
  )
  printf '%s\n' "${defaults[@]}"
  # Per-workspace git remotes are workspace-specific state. Callers that produce
  # cross-workspace artifacts (e.g. the shared `_generate_cache.sh` cache file)
  # set DCTL_NET_OMIT_GIT_REMOTES=1 to keep git-remote hosts out of the
  # composed list; runtime injection in krun.sh always recomputes the full
  # list per workspace, so omitting here is safe for the cache path.
  if [[ ${DCTL_NET_OMIT_GIT_REMOTES:-0} != 1 ]]; then
    _net_default_allowlist_git_remotes
  fi
}

_net_default_allowlist_git_remotes() {
  local url host
  while IFS=$'\t' read -r _ url _; do
    host="$(_net_host_from_remote_url "$url")"
    [[ -n $host ]] && printf '%s\n' "$host"
  done < <(git -C "$WORKSPACE_FOLDER" remote -v 2>/dev/null | awk '{print $1"\t"$2"\t"$3}' | sort -u)
}

_net_host_from_remote_url() {
  local url="$1"
  if [[ $url =~ ^[A-Za-z][A-Za-z0-9+.-]*://([^/:]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  elif [[ $url =~ ^[^@[:space:]]+@([^:]+): ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  fi
}
