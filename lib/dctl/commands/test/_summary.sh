# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_TEST_SUMMARY_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_TEST_SUMMARY_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

check_pass() {
  _check_names+=("$1")
  _check_results+=("PASS")
  printf '\033[1;32mPASS:\033[0m %s\n' "$1"
}

check_fail() {
  _check_names+=("$1")
  _check_results+=("FAIL")
  printf '\033[1;31mFAIL:\033[0m %s\n' "$1"
}

_print_summary() {
  local passed=0 failed=0
  local i

  printf '\n\033[1m── Summary ──────────────────────────────\033[0m\n'
  if [[ -n ${DCTL_CONFIG_STATUS:-} ]]; then
    case "$DCTL_CONFIG_STATUS" in
      cached) printf '  \033[1;36mℹ\033[0m Config: using cached devcontainer.json\n' ;;
      generated) printf '  \033[1;36mℹ\033[0m Config: generated new devcontainer.json\n' ;;
      existing) printf '  \033[1;36mℹ\033[0m Config: using existing registered config\n' ;;
    esac
  fi
  for i in "${!_check_names[@]}"; do
    if [[ ${_check_results[$i]} == "PASS" ]]; then
      printf '  \033[1;32m✔\033[0m %s\n' "${_check_names[$i]}"
      passed=$((passed + 1))
    else
      printf '  \033[1;31m✘\033[0m %s\n' "${_check_names[$i]}"
      failed=$((failed + 1))
    fi
  done
  printf '\033[1m── %d passed, %d failed ──────────────────\033[0m\n' "$passed" "$failed"
}
