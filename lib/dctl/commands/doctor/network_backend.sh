# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_DOCTOR_NETWORK_BACKEND_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_DOCTOR_NETWORK_BACKEND_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require commands/doctor/_helpers.sh

_doctor_probe_11_network_backend() {
  local label="podman rootless network backend"
  local value=""

  if ! _doctor_require_cmd podman; then
    _doctor_check_fail "$label" "Install podman and rerun 'dctl doctor'."
    return
  fi

  value="$(podman info --format '{{.Host.NetworkBackend}}' 2>/dev/null || true)"
  if [[ -n $value ]]; then
    _doctor_check_pass "podman network backend = ${value}"
  else
    _doctor_check_fail "$label" "Failed to read 'podman info --format {{.Host.NetworkBackend}}'. Verify podman is configured correctly and rerun the doctor."
  fi
}

cmd_doctor_network_backend() {
  _doctor_probe_11_network_backend
}
