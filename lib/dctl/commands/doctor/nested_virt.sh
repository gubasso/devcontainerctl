# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_DOCTOR_NESTED_VIRT_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_DOCTOR_NESTED_VIRT_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require commands/doctor/_helpers.sh

_doctor_probe_14_nested_virt() {
  local label="cpuinfo advertises vmx/svm nested-virt hints"

  if grep -qE 'vmx|svm' /proc/cpuinfo 2>/dev/null; then
    _doctor_check_pass "$label"
  else
    _doctor_check_warn "$label" "No vmx/svm flag — you may be inside a VM without nested virtualization. libkrun may still run but with significant performance loss."
  fi
}

cmd_doctor_nested_virt() {
  _doctor_probe_14_nested_virt
}
