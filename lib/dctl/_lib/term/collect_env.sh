# shellcheck shell=bash

[[ -n ${_DCTL_LIB_TERM_COLLECT_ENV_LOADED:-} ]] && return 0
readonly _DCTL_LIB_TERM_COLLECT_ENV_LOADED=1

collect_term_env() {
  local -n out="$1"
  out=()

  local var_name
  for var_name in TERM COLORTERM TERM_PROGRAM TERM_PROGRAM_VERSION KITTY_WINDOW_ID KITTY_LISTEN_ON; do
    if [[ -n ${!var_name:-} ]]; then
      out+=(--remote-env "${var_name}=${!var_name}")
    fi
  done
}
