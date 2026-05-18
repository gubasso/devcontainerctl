# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_DOCTOR_HELPERS_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_DOCTOR_HELPERS_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh

_doctor_names=()
_doctor_results=()
_doctor_remediations=()

_doctor_crun_ok=false
_doctor_krun_ok=false

_doctor_style() {
  if command -v tput >/dev/null 2>&1 && [[ -n ${TERM:-} ]] && [[ $TERM != "dumb" ]]; then
    tput "$@" 2>/dev/null || true
  fi
}

_doctor_green() {
  _doctor_style setaf 2
}

_doctor_yellow() {
  _doctor_style setaf 3
}

_doctor_red() {
  _doctor_style setaf 1
}

_doctor_bold() {
  _doctor_style bold
}

_doctor_reset() {
  _doctor_style sgr0
}

_doctor_check_pass() {
  _doctor_names+=("$1")
  _doctor_results+=("PASS")
  _doctor_remediations+=("")
  printf '%sPASS:%s %s\n' "$(_doctor_green)" "$(_doctor_reset)" "$1"
}

_doctor_check_fail() {
  _doctor_names+=("$1")
  _doctor_results+=("FAIL")
  _doctor_remediations+=("$2")
  printf '%sFAIL:%s %s\n' "$(_doctor_red)" "$(_doctor_reset)" "$1"
  printf '  %s\n' "$2" >&2
}

_doctor_check_warn() {
  _doctor_names+=("$1")
  _doctor_results+=("WARN")
  _doctor_remediations+=("$2")
  printf '%sWARN:%s %s\n' "$(_doctor_yellow)" "$(_doctor_reset)" "$1"
  printf '  %s\n' "$2" >&2
}

_doctor_print_summary() {
  local passed=0 warned=0 failed=0
  local i glyph color

  printf '\n%s── Summary ──────────────────────────────%s\n' \
    "$(_doctor_bold)" "$(_doctor_reset)"
  for i in "${!_doctor_names[@]}"; do
    case "${_doctor_results[$i]}" in
      PASS)
        glyph="✔"
        color="$(_doctor_green)"
        passed=$((passed + 1))
        ;;
      WARN)
        glyph="⚠"
        color="$(_doctor_yellow)"
        warned=$((warned + 1))
        ;;
      *)
        glyph="✘"
        color="$(_doctor_red)"
        failed=$((failed + 1))
        ;;
    esac
    printf '  %s%s%s %s\n' "$color" "$glyph" "$(_doctor_reset)" "${_doctor_names[$i]}"
  done
  printf '%s── %d passed, %d warned, %d failed ───────────────%s\n' \
    "$(_doctor_bold)" "$passed" "$warned" "$failed" "$(_doctor_reset)"

  [[ $failed -eq 0 ]]
}

_doctor_require_cmd() {
  (require_cmd "$1") >/dev/null 2>&1
}

_doctor_current_user() {
  if [[ -n ${USER:-} ]]; then
    printf '%s\n' "$USER"
    return
  fi

  id -un 2>/dev/null || true
}

_doctor_cleanup_smoke() {
  local ctr="$1"
  podman rm -f "$ctr" >/dev/null 2>&1 || true
}
