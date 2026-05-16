# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_DOCTOR_USERNS_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_DOCTOR_USERNS_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require commands/doctor/_helpers.sh

_doctor_probe_12_uid_map() {
  local label="podman unshare exposes a multi-line uid_map"
  local lines=""

  if ! _doctor_require_cmd podman; then
    _doctor_check_fail "$label" "Install podman and rerun 'dctl doctor'."
    return
  fi

  lines="$(podman unshare cat /proc/self/uid_map 2>/dev/null | wc -l | tr -d ' ')"
  if [[ $lines =~ ^[0-9]+$ ]] && [[ $lines -ge 2 ]]; then
    _doctor_check_pass "$label"
  else
    _doctor_check_fail "$label" "User namespace mapping is not working. Verify probe 7 (/etc/subuid, /etc/subgid) and run 'podman system migrate'."
  fi
}

_doctor_probe_13_userns_clone() {
  local label="kernel.unprivileged_userns_clone == 1"
  local value=""

  if ! _doctor_require_cmd sysctl; then
    _doctor_check_warn "$label" "Install procps so 'dctl doctor' can inspect kernel.unprivileged_userns_clone."
    return
  fi

  value="$(sysctl -n kernel.unprivileged_userns_clone 2>/dev/null || echo 1)"
  if [[ $value == "1" ]]; then
    _doctor_check_pass "$label"
  else
    _doctor_check_warn "$label" "Set 'kernel.unprivileged_userns_clone = 1' in /etc/sysctl.d/."
  fi
}

cmd_doctor_userns() {
  _doctor_probe_12_uid_map
  _doctor_probe_13_userns_clone
}
