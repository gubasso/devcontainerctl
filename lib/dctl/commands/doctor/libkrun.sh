# shellcheck shell=bash

[[ -n ${_DCTL_COMMANDS_DOCTOR_LIBKRUN_LOADED:-} ]] && return 0
readonly _DCTL_COMMANDS_DOCTOR_LIBKRUN_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/_lib/source.sh"

__dctl_require _lib/log.sh
__dctl_require _lib/paths.sh
__dctl_require commands/doctor/_helpers.sh
__dctl_require runtime/common.sh

_doctor_probe_4_libkrun_version() {
  local label="libkrun version >= ${MIN_LIBKRUN_VER}"
  local lib_path version soname

  if ! _doctor_require_cmd ldconfig; then
    _doctor_check_fail "$label" "Install glibc tooling that provides 'ldconfig' so 'dctl doctor' can locate libkrun.so."
    return
  fi
  if ! _doctor_require_cmd readlink; then
    _doctor_check_fail "$label" "Install coreutils with readlink support so 'dctl doctor' can resolve libkrun.so."
    return
  fi

  lib_path="$(ldconfig -p 2>/dev/null | awk '/libkrun\.so/{print $4; exit}')"
  if [[ -z $lib_path ]]; then
    _doctor_check_fail "$label" "libkrun.so not found via ldconfig. Install the 'libkrun' package (Tumbleweed: enable OBS Virtualization repo and 'sudo zypper in libkrun libkrunfw'; official Tumbleweed repos ship <= 1.15.1 which is below MIN_LIBKRUN_VER=${MIN_LIBKRUN_VER})."
    return
  fi

  lib_path="$(readlink -f "$lib_path" 2>/dev/null || printf '%s' "$lib_path")"
  version="$(printf '%s' "$lib_path" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+$' || true)"
  if [[ -z $version ]]; then
    if ! _doctor_require_cmd readelf; then
      _doctor_check_fail "$label" "Install binutils so 'dctl doctor' can inspect libkrun.so when the resolved path does not encode a version."
      return
    fi
    soname="$(readelf -d "$lib_path" 2>/dev/null | awk '/SONAME/{gsub(/[][]/, "", $5); print $5; exit}')"
    version="$(printf '%s' "$soname" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+$' || true)"
  fi

  if [[ -z $version ]]; then
    _doctor_check_fail "$label" "Could not extract libkrun version from $lib_path. File a bug."
    return
  fi

  if [[ "$(printf '%s\n%s\n' "$MIN_LIBKRUN_VER" "$version" | sort -V | head -n1)" == "$MIN_LIBKRUN_VER" ]]; then
    _doctor_check_pass "$label"
  else
    _doctor_check_fail "$label" "Installed libkrun version is ${version}; require >= ${MIN_LIBKRUN_VER}. Enable the OBS Virtualization repo and install newer 'libkrun' and 'libkrunfw' packages."
  fi
}

cmd_doctor_libkrun() {
  _doctor_probe_4_libkrun_version
}
