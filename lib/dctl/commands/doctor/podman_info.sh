# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_DOCTOR_PODMAN_INFO_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_DOCTOR_PODMAN_INFO_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require commands/doctor/_helpers.sh
__dctl_require runtime/common.sh

_doctor_probe_3_podman_krun_smoke() {
  local label="podman + krun smoke"
  local ctr="dctl-doctor-smoke-$$"
  local rt=""
  local err_file stderr_excerpt

  if ! _doctor_require_cmd podman; then
    _doctor_check_warn "$label" "Skipped because podman is not installed yet. Install podman first, then rerun 'dctl doctor'."
    return
  fi

  # shellcheck disable=SC2154
  # _doctor_{crun,krun}_ok are set by commands/doctor/crun_libkrun.sh probes
  # 1 and 2, which always run before this probe per cmd_doctor's order.
  if [[ $_doctor_crun_ok != true || $_doctor_krun_ok != true ]]; then
    _doctor_check_warn "$label" "Skipped because the crun/libkrun prerequisites failed above. Fix probes 1 and 2, then rerun 'dctl doctor'."
    return
  fi

  _doctor_cleanup_smoke "$ctr"
  err_file="$(mktemp)"
  if ! podman create --runtime krun --name "$ctr" \
    "$DCTL_DOCTOR_SMOKE_IMAGE" /bin/true >/dev/null 2>"$err_file"; then
    stderr_excerpt="$(head -n 5 "$err_file" 2>/dev/null | sed 's/^/      /')"
    rm -f "$err_file"
    _doctor_check_fail "$label" "podman create failed. stderr:
${stderr_excerpt:-      <no output>}
    Reproduce: podman create --runtime krun --name $ctr ${DCTL_DOCTOR_SMOKE_IMAGE} /bin/true"
    _doctor_cleanup_smoke "$ctr"
    return
  fi
  rm -f "$err_file"

  err_file="$(mktemp)"
  if ! podman start -a "$ctr" >/dev/null 2>"$err_file"; then
    stderr_excerpt="$(head -n 5 "$err_file" 2>/dev/null | sed 's/^/      /')"
    rm -f "$err_file"
    _doctor_check_fail "$label" "Container failed to start under krun. stderr:
${stderr_excerpt:-      <no output>}
    Check /dev/kvm permissions (probe 5), the ACL warning (probe 5b), and 'journalctl --user -xe'."
    _doctor_cleanup_smoke "$ctr"
    return
  fi
  rm -f "$err_file"

  rt="$(podman inspect --format '{{.OCIRuntime}}' "$ctr" 2>/dev/null || true)"
  if [[ $rt == "krun" ]]; then
    _doctor_check_pass "$label"
  else
    _doctor_check_fail "$label" "Container ran but reported OCIRuntime='${rt:-<empty>}' ; expected 'krun'. Verify 'podman info --format {{.Host.OCIRuntime.Name}}' and the --runtime flag wiring."
  fi

  _doctor_cleanup_smoke "$ctr"
}

_doctor_probe_10_oci_runtime() {
  local label="podman default OCI runtime"
  local value=""

  if ! _doctor_require_cmd podman; then
    _doctor_check_fail "$label" "Install podman and rerun 'dctl doctor'."
    return
  fi

  value="$(podman info --format '{{.Host.OCIRuntime.Name}}' 2>/dev/null || true)"
  if [[ -n $value ]]; then
    _doctor_check_pass "default OCI runtime = ${value} (krun is invoked via --runtime krun)"
  else
    _doctor_check_fail "$label" "Failed to read 'podman info --format {{.Host.OCIRuntime.Name}}'. Verify podman is configured correctly and rerun the doctor."
  fi
}

_doctor_probe_10b_parallel() {
  local label="GNU parallel (bats --jobs)"

  if _doctor_require_cmd parallel; then
    _doctor_check_pass "$label"
  else
    _doctor_check_warn "$label" "Install GNU parallel to enable 'bats --jobs N'. Without it, 'make test-unit' and the bats pre-commit hooks will fail under --jobs."
  fi
}

cmd_doctor_podman_info() {
  _doctor_probe_3_podman_krun_smoke
  _doctor_probe_10_oci_runtime
  _doctor_probe_10b_parallel
}
