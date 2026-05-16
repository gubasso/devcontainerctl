# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_DOCTOR_SUBID_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_DOCTOR_SUBID_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require commands/doctor/_helpers.sh

_doctor_probe_7_subid() {
  local label="/etc/subuid and /etc/subgid allocate a range to the current user"
  local current_user=""

  current_user="$(_doctor_current_user)"

  if [[ -n $current_user ]] \
    && grep -q "^${current_user}:" /etc/subuid 2>/dev/null \
    && grep -q "^${current_user}:" /etc/subgid 2>/dev/null; then
    _doctor_check_pass "$label"
  else
    _doctor_check_fail "$label" "Run 'sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 \$USER && podman system migrate'."
  fi
}

cmd_doctor_subid() {
  _doctor_probe_7_subid
}
