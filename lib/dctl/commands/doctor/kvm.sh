# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_DOCTOR_KVM_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_DOCTOR_KVM_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require commands/doctor/_helpers.sh
__dctl_require commands/doctor/crun_libkrun.sh
__dctl_require commands/doctor/libkrun.sh

_doctor_probe_5_kvm_access() {
  local label="current user has rw access to /dev/kvm"

  if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    _doctor_check_pass "$label"
  else
    _doctor_check_fail "$label" "Run 'sudo usermod -aG kvm \$USER && newgrp kvm' (group membership is not retroactive in the current shell — newgrp or re-login is required)."
  fi
}

_doctor_probe_5b_kvm_acl() {
  local label="/dev/kvm POSIX ACL for current user"
  local current_user=""

  current_user="$(_doctor_current_user)"

  if ! _doctor_require_cmd getfacl; then
    _doctor_check_warn "$label" "Install the 'acl' package to inspect the /dev/kvm POSIX ACL for the crun#1894 trap."
    return
  fi

  if [[ -n $current_user ]] \
    && getfacl /dev/kvm 2>/dev/null | grep -q "user:${current_user}:rw"; then
    _doctor_check_pass "$label"
    return
  fi

  _doctor_check_warn "$label" "Standard 'kvm' group membership may be insufficient for krun (crun#1894). If probe 3 fails, run 'sudo setfacl -m u:\$USER:rw /dev/kvm'. Note: ACLs are not persistent across reboots on some distros."
}

_doctor_minimal_preflight() {
  local failed=0

  if ! (
    _doctor_names=()
    _doctor_results=()
    _doctor_remediations=()
    _doctor_crun_ok=false
    _doctor_krun_ok=false

    _doctor_check_pass() {
      _doctor_names+=("$1")
      _doctor_results+=("PASS")
      _doctor_remediations+=("")
    }

    _doctor_check_fail() {
      _doctor_names+=("$1")
      _doctor_results+=("FAIL")
      _doctor_remediations+=("$2")
    }

    _doctor_check_warn() {
      _doctor_names+=("$1")
      _doctor_results+=("WARN")
      _doctor_remediations+=("$2")
    }

    _doctor_probe_1_crun_libkrun >/dev/null 2>&1
    _doctor_probe_2_krun_symlink >/dev/null 2>&1
    _doctor_probe_4_libkrun_version >/dev/null 2>&1
    _doctor_probe_5_kvm_access >/dev/null 2>&1
    _doctor_probe_5b_kvm_acl >/dev/null 2>&1

    local result
    for result in "${_doctor_results[@]}"; do
      [[ $result == "FAIL" ]] && exit 1
    done
    exit 0
  ); then
    failed=1
  fi

  [[ $failed -eq 0 ]]
}

_doctor_probe_6_kvm_group() {
  local label="current user is in the kvm group"
  local current_user=""

  current_user="$(_doctor_current_user)"

  if ! _doctor_require_cmd id; then
    _doctor_check_fail "$label" "Install coreutils/shadow tooling that provides 'id' so 'dctl doctor' can check group membership."
    return
  fi

  if [[ -n $current_user ]] \
    && id -nG "$current_user" 2>/dev/null | tr ' ' '\n' | grep -qx kvm; then
    _doctor_check_pass "$label"
  else
    _doctor_check_fail "$label" "Run 'sudo usermod -aG kvm \$USER && newgrp kvm'."
  fi
}

cmd_doctor_kvm() {
  _doctor_probe_5_kvm_access
  _doctor_probe_5b_kvm_acl
  _doctor_probe_6_kvm_group
}
