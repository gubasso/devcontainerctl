# shellcheck shell=bash
# Host preflight doctor for the libkrun + rootless Podman stack
# (sourced, not executed directly)

[[ -n ${_DCTL_DOCTOR_LOADED:-} ]] && return 0
readonly _DCTL_DOCTOR_LOADED=1

: "${DCTL_LIB_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"

# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/common.sh"
# shellcheck source=/dev/null
source "${DCTL_LIB_DIR}/runtime/common.sh"

_doctor_names=()
_doctor_results=()
_doctor_remediations=()

_doctor_crun_ok=false
_doctor_krun_ok=false

_doctor_style() {
  if command -v tput >/dev/null 2>&1 && [[ -n ${TERM:-} ]] && [[ $TERM != "dumb" ]]; then
    tput "$@" 2>/dev/null || true
  fi
}

_doctor_green() {
  _doctor_style setaf 2
}

_doctor_yellow() {
  _doctor_style setaf 3
}

_doctor_red() {
  _doctor_style setaf 1
}

_doctor_bold() {
  _doctor_style bold
}

_doctor_reset() {
  _doctor_style sgr0
}

_doctor_check_pass() {
  _doctor_names+=("$1")
  _doctor_results+=("PASS")
  _doctor_remediations+=("")
  printf '%sPASS:%s %s\n' "$(_doctor_green)" "$(_doctor_reset)" "$1"
}

_doctor_check_fail() {
  _doctor_names+=("$1")
  _doctor_results+=("FAIL")
  _doctor_remediations+=("$2")
  printf '%sFAIL:%s %s\n' "$(_doctor_red)" "$(_doctor_reset)" "$1"
  printf '  %s\n' "$2" >&2
}

_doctor_check_warn() {
  _doctor_names+=("$1")
  _doctor_results+=("WARN")
  _doctor_remediations+=("$2")
  printf '%sWARN:%s %s\n' "$(_doctor_yellow)" "$(_doctor_reset)" "$1"
  printf '  %s\n' "$2" >&2
}

_doctor_print_summary() {
  local passed=0 warned=0 failed=0
  local i glyph color

  printf '\n%s── Summary ──────────────────────────────%s\n' \
    "$(_doctor_bold)" "$(_doctor_reset)"
  for i in "${!_doctor_names[@]}"; do
    case "${_doctor_results[$i]}" in
      PASS)
        glyph="✔"
        color="$(_doctor_green)"
        passed=$((passed + 1))
        ;;
      WARN)
        glyph="⚠"
        color="$(_doctor_yellow)"
        warned=$((warned + 1))
        ;;
      *)
        glyph="✘"
        color="$(_doctor_red)"
        failed=$((failed + 1))
        ;;
    esac
    printf '  %s%s%s %s\n' "$color" "$glyph" "$(_doctor_reset)" "${_doctor_names[$i]}"
  done
  printf '%s── %d passed, %d warned, %d failed ───────────────%s\n' \
    "$(_doctor_bold)" "$passed" "$warned" "$failed" "$(_doctor_reset)"

  [[ $failed -eq 0 ]]
}

_doctor_require_cmd() {
  (require_cmd "$1") >/dev/null 2>&1
}

_doctor_current_user() {
  if [[ -n ${USER:-} ]]; then
    printf '%s\n' "$USER"
    return
  fi

  id -un 2>/dev/null || true
}

_doctor_cleanup_smoke() {
  local ctr="$1"
  podman rm -f "$ctr" >/dev/null 2>&1 || true
}

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

_doctor_probe_3_podman_krun_smoke() {
  local label="podman + krun smoke"
  local ctr="dctl-doctor-smoke-$$"
  local rt=""

  if ! _doctor_require_cmd podman; then
    _doctor_check_warn "$label" "Skipped because podman is not installed yet. Install podman first, then rerun 'dctl doctor'."
    return
  fi

  if [[ $_doctor_crun_ok != true || $_doctor_krun_ok != true ]]; then
    _doctor_check_warn "$label" "Skipped because the crun/libkrun prerequisites failed above. Fix probes 1 and 2, then rerun 'dctl doctor'."
    return
  fi

  _doctor_cleanup_smoke "$ctr"
  if ! podman create --runtime krun --name "$ctr" \
    "$DCTL_DOCTOR_SMOKE_IMAGE" /bin/true >/dev/null 2>&1; then
    _doctor_check_fail "$label" "podman create failed. Verify image access to ${DCTL_DOCTOR_SMOKE_IMAGE}; if the registry is unreachable, retry later. Otherwise run 'podman create --runtime krun --name $ctr ${DCTL_DOCTOR_SMOKE_IMAGE} /bin/true' manually and inspect the error."
    _doctor_cleanup_smoke "$ctr"
    return
  fi

  if ! podman start -a "$ctr" >/dev/null 2>&1; then
    _doctor_check_fail "$label" "Container failed to start under krun. Check /dev/kvm permissions (probe 5), the ACL warning (probe 5b), and 'journalctl --user -xe' for podman/crun diagnostics."
    _doctor_cleanup_smoke "$ctr"
    return
  fi

  rt="$(podman inspect --format '{{.OCIRuntime}}' "$ctr" 2>/dev/null || true)"
  if [[ $rt == "krun" ]]; then
    _doctor_check_pass "$label"
  else
    _doctor_check_fail "$label" "Container ran but reported OCIRuntime='${rt:-<empty>}' ; expected 'krun'. Verify 'podman info --format {{.Host.OCIRuntime.Name}}' and the --runtime flag wiring."
  fi

  _doctor_cleanup_smoke "$ctr"
}

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

_doctor_probe_14_nested_virt() {
  local label="cpuinfo advertises vmx/svm nested-virt hints"

  if grep -qE 'vmx|svm' /proc/cpuinfo 2>/dev/null; then
    _doctor_check_pass "$label"
  else
    _doctor_check_warn "$label" "No vmx/svm flag — you may be inside a VM without nested virtualization. libkrun may still run but with significant performance loss."
  fi
}

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
