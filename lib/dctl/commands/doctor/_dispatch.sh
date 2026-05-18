# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_DOCTOR_DISPATCH_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_DOCTOR_DISPATCH_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require commands/doctor/_helpers.sh
__dctl_require commands/doctor/crun_libkrun.sh
__dctl_require commands/doctor/podman_info.sh
__dctl_require commands/doctor/libkrun.sh
__dctl_require commands/doctor/kvm.sh
__dctl_require commands/doctor/subid.sh
__dctl_require commands/doctor/cgroups.sh
__dctl_require commands/doctor/network_backend.sh
__dctl_require commands/doctor/userns.sh
__dctl_require commands/doctor/nested_virt.sh

usage_doctor() {
  cat <<'EOF'
Usage: dctl doctor [options]

Probe the host for libkrun + rootless Podman readiness.

Options:
  --help, -h    Show this help text
EOF
}

cmd_doctor() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help | -h)
        usage_doctor
        return 0
        ;;
      *)
        err "Unknown doctor option: $1"
        ;;
    esac
  done

  _doctor_names=()
  _doctor_results=()
  _doctor_remediations=()
  _doctor_crun_ok=false
  _doctor_krun_ok=false

  log "Running host preflight for libkrun + rootless Podman"
  # Probes are invoked directly (not via the per-file cmd_doctor_<file>
  # wrappers) because the operator-facing print order 1..14 spans files —
  # podman_info.sh groups probes 3 and 10, which are not consecutive in
  # the original sequence. Wrappers exist to satisfy structure_test's
  # one-cmd-per-file invariant.
  _doctor_probe_1_crun_libkrun
  _doctor_probe_2_krun_symlink
  _doctor_probe_3_podman_krun_smoke
  _doctor_probe_4_libkrun_version
  _doctor_probe_5_kvm_access
  _doctor_probe_5b_kvm_acl
  _doctor_probe_6_kvm_group
  _doctor_probe_7_subid
  _doctor_probe_8_cgroup_v2
  _doctor_probe_9_cgroup_manager
  _doctor_probe_10_oci_runtime
  _doctor_probe_10b_parallel
  _doctor_probe_11_network_backend
  _doctor_probe_12_uid_map
  _doctor_probe_13_userns_clone
  _doctor_probe_14_nested_virt

  if _doctor_print_summary; then
    log "Doctor checks passed"
    return 0
  fi

  return 1
}

main_doctor() {
  cmd_doctor "$@"
}
