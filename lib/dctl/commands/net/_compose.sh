# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_NET_COMPOSE_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_NET_COMPOSE_LOADED=1

__dctl_require _lib/log.sh
__dctl_require commands/net/_default_allowlist.sh
__dctl_require commands/net/_user_allowlist.sh

net_compose_allowlist() {
  local workspace_folder="${1:-$WORKSPACE_FOLDER}"
  {
    net_default_allowlist
    net_user_allowlist "$workspace_folder"
  } | while IFS= read -r entry; do
    [[ -n $entry ]] || continue
    entry="$(_net_normalize_allowlist_entry "$entry")"
    if _net_allowlist_entry_valid "$entry"; then
      printf '%s\n' "$entry"
    else
      warn "Ignoring invalid network allowlist entry: $entry"
    fi
  done | LC_ALL=C sort -u
}

net_compose_allowlist_json() {
  local workspace_folder="${1:-$WORKSPACE_FOLDER}"
  net_compose_allowlist "$workspace_folder" | jq -Rcs 'split("\n") | map(select(length > 0))'
}

net_compose_allowlist_annotated() {
  local workspace_folder="${1:-$WORKSPACE_FOLDER}"
  local entry normalized
  declare -A seen=()

  while IFS= read -r entry; do
    [[ -n $entry ]] || continue
    normalized="$(_net_normalize_allowlist_entry "$entry")"
    if _net_allowlist_entry_valid "$normalized" && [[ -z ${seen[$normalized]:-} ]]; then
      seen["$normalized"]=1
      printf '%s\t%s\n' "$normalized" "default"
    fi
  done < <(_net_default_allowlist_static)

  while IFS= read -r entry; do
    [[ -n $entry ]] || continue
    normalized="$(_net_normalize_allowlist_entry "$entry")"
    if _net_allowlist_entry_valid "$normalized" && [[ -z ${seen[$normalized]:-} ]]; then
      seen["$normalized"]=1
      printf '%s\t%s\n' "$normalized" "git-remote"
    fi
  done < <(_net_default_allowlist_git_remotes)

  while IFS= read -r entry; do
    [[ -n $entry ]] || continue
    normalized="$(_net_normalize_allowlist_entry "$entry")"
    if _net_allowlist_entry_valid "$normalized" && [[ -z ${seen[$normalized]:-} ]]; then
      seen["$normalized"]=1
      printf '%s\t%s\n' "$normalized" "user"
    fi
  done < <(net_user_allowlist "$workspace_folder")
}

_net_default_allowlist_static() {
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
}

_net_normalize_allowlist_entry() {
  local entry="$1"
  printf '%s\n' "${entry,,}"
}

_net_allowlist_entry_valid() {
  local entry="$1"
  [[ -n $entry ]] || return 1
  [[ $entry =~ ^\*\.[a-z0-9.-]+$ ]] && return 0
  [[ $entry =~ ^[a-z0-9.-]+$ ]] && return 0
  [[ $entry =~ ^[0-9.]+/[0-9]+$ ]] && return 0
  [[ $entry =~ ^[0-9a-f:]+/[0-9]+$ ]] && return 0
  return 1
}
