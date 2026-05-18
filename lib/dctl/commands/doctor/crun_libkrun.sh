# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_DOCTOR_CRUN_LIBKRUN_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_DOCTOR_CRUN_LIBKRUN_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require commands/doctor/_helpers.sh

_doctor_probe_1_crun_libkrun() {
  local label="crun built with +LIBKRUN feature tag"
  if ! _doctor_require_cmd crun; then
    _doctor_check_fail "$label" "Install crun built with libkrun handler (Tumbleweed: 'sudo zypper in crun crun-krun' once available, or build crun with --enable-handler-libkrun). Do not check 'crun --help' for '--krun' — that flag does not exist."
    return
  fi

  if crun --version 2>/dev/null | grep -q '+LIBKRUN'; then
    _doctor_crun_ok=true
    _doctor_check_pass "$label"
  else
    _doctor_check_fail "$label" "Install crun built with libkrun handler (Tumbleweed: 'sudo zypper in crun crun-krun' once available, or build crun with --enable-handler-libkrun). Do not check 'crun --help' for '--krun' — that flag does not exist."
  fi
}

_doctor_probe_2_krun_symlink() {
  local label="krun symlink resolves to crun"
  local krun_path resolved

  if ! _doctor_require_cmd readlink; then
    _doctor_check_fail "$label" "Install coreutils with readlink support so 'dctl doctor' can verify the krun → crun symlink."
    return
  fi

  if ! krun_path="$(command -v krun 2>/dev/null)"; then
    _doctor_check_fail "$label" "Install the crun-krun integration that ships the /usr/bin/krun → /usr/bin/crun symlink (Fedora: crun-krun; Tumbleweed: bundled with crun in the OBS Virtualization repo)."
    return
  fi

  resolved="$(readlink -f "$krun_path" 2>/dev/null || true)"
  if [[ $resolved == */crun ]]; then
    _doctor_krun_ok=true
    _doctor_check_pass "$label"
  else
    _doctor_check_fail "$label" "Install the crun-krun integration that ships the /usr/bin/krun → /usr/bin/crun symlink (Fedora: crun-krun; Tumbleweed: bundled with crun in the OBS Virtualization repo)."
  fi
}

cmd_doctor_crun_libkrun() {
  _doctor_probe_1_crun_libkrun
  _doctor_probe_2_krun_symlink
}
