# shellcheck shell=bash

[[ -n ${_DCTL_LIB_FZF_LOADED:-} ]] && return 0
readonly _DCTL_LIB_FZF_LOADED=1

_fzf_pick() {
  local prompt="$1"
  local header="$2"
  local preview_cmd="${3:-}"

  local -a args
  args=(
    --height=~50%
    --layout=reverse
    --border
    --prompt="$prompt"
    --header="$header"
  )

  if [[ -n $preview_cmd ]]; then
    args+=(--preview "$preview_cmd" --preview-window "right:60%:wrap")
  fi

  fzf "${args[@]}"
}
