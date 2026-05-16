# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_DOCTOR_CGROUPS_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_DOCTOR_CGROUPS_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require commands/doctor/_helpers.sh

_doctor_probe_8_cgroup_v2() {
  local label="podman reports cgroups v2"
  local value=""

  if ! _doctor_require_cmd podman; then
    _doctor_check_fail "$label" "Install podman and rerun 'dctl doctor'."
    return
  fi

  value="$(podman info --format '{{.Host.CgroupVersion}}' 2>/dev/null || true)"
  if [[ $value == "v2" ]]; then
    _doctor_check_pass "$label"
  else
    _doctor_check_fail "$label" "Rootless Podman requires cgroups v2. Verify /sys/fs/cgroup/cgroup.controllers exists and see https://access.redhat.com/solutions/5913671 ."
  fi
}

_doctor_probe_9_cgroup_manager() {
  local label="podman uses the systemd cgroup manager"
  local value=""

  if ! _doctor_require_cmd podman; then
    _doctor_check_fail "$label" "Install podman and rerun 'dctl doctor'."
    return
  fi

  value="$(podman info --format '{{.Host.CgroupManager}}' 2>/dev/null || true)"
  if [[ $value == "systemd" ]]; then
    _doctor_check_pass "$label"
  else
    _doctor_check_fail "$label" "Set 'cgroup_manager = \"systemd\"' in ~/.config/containers/containers.conf and rerun 'podman system migrate'."
  fi
}

cmd_doctor_cgroups() {
  _doctor_probe_8_cgroup_v2
  _doctor_probe_9_cgroup_manager
}
