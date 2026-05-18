#!/usr/bin/env bats

# bats file_tags=unit

load test_helper

source_runtime() {
  local repo_root
  repo_root="${BATS_TEST_DIRNAME}/.."
  readonly DCTL_LIB_DIR="${repo_root}/lib/dctl"
  set -euo pipefail
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/_lib/source.sh"
  __dctl_require _lib/log.sh
  __dctl_require _lib/paths.sh
  __dctl_require _lib/auth/gh_token.sh
  __dctl_require _lib/auth/glab_token.sh
  __dctl_require _lib/workspace/label_filter.sh
  __dctl_require commands/net/_compose.sh
  __dctl_require commands/ws/_helpers.sh
  __dctl_require commands/doctor/_helpers.sh
  __dctl_require commands/doctor/crun_libkrun.sh
  __dctl_require commands/doctor/libkrun.sh
  __dctl_require commands/doctor/kvm.sh
  __dctl_require runtime/common.sh
  __dctl_require runtime/krun.sh
}

create_runtime_fixture() {
  mkdir -p "${WORKSPACE_FOLDER}/.devcontainer"
  cat >"${WORKSPACE_FOLDER}/.devcontainer/devcontainer.json" <<'EOF'
{
  "image": "devimg/agents:latest",
  "remoteUser": "dev",
  "workspaceFolder": "/workspaces/app",
  "remoteEnv": {
    "APP_MODE": "test"
  }
}
EOF
}

setup() {
  setup_test_fixtures
  export XDG_DATA_HOME="${TEST_TMPDIR}/xdg-data"
  export XDG_CONFIG_HOME="${TEST_TMPDIR}/xdg-config"
  export XDG_CACHE_HOME="${TEST_TMPDIR}/xdg-cache"
  export WORKSPACE_FOLDER="${TEST_TMPDIR}/workspace"
  mkdir -p "${XDG_DATA_HOME}/dctl" "${XDG_CONFIG_HOME}/dctl" "${XDG_CACHE_HOME}/dctl" "$WORKSPACE_FOLDER"
  source_runtime
  create_runtime_fixture
  enable_mocks
  unset _DCTL_KRUN_PREFLIGHT_OK DCTL_KRUN_HTTP2_WORKAROUND GH_TOKEN GITHUB_TOKEN GITLAB_TOKEN TERM COLORTERM 2>/dev/null || true
  # shellcheck disable=SC2329
  run_postcreate() { :; }
  # shellcheck disable=SC2329
  run_poststart() { :; }
}

teardown() {
  teardown_test_fixtures
}

# Round 60 pins the current hook contract from runtime/krun.sh: the libkrun
# #674 hook is reserved but inactive, so toggling DCTL_KRUN_HTTP2_WORKAROUND
# must remain a no-op until a later source round deliberately activates it.
@test "rt_run emits krun podman argv without auth token env flags" {
  # shellcheck disable=SC2030
  export _DCTL_KRUN_PREFLIGHT_OK=1
  record_argv_mock podman 0 "ctr123"

  run rt_run "$WORKSPACE_FOLDER" "${WORKSPACE_FOLDER}/.devcontainer/devcontainer.json"
  [ "$status" -eq 0 ]
  [ "$output" = "ctr123" ]
  assert_argv_call podman 1 image inspect devimg/agents:latest
  assert_argv_contains_sequence podman 2 run --runtime krun --detach
  assert_argv_contains_sequence podman 2 --label "devcontainer.local_folder=${WORKSPACE_FOLDER}"
  assert_argv_contains_sequence podman 2 --annotation krun.ram_mib=4096 --annotation krun.cpus=2
  assert_mock_called "DCTL_NETWORK_ALLOWLIST_JSON="
  assert_mock_not_called "GH_TOKEN="
  assert_mock_not_called "GITLAB_TOKEN="
}

@test "rt_exec emits remote env and forwarded auth tokens on podman exec" {
  # shellcheck disable=SC2030,SC2031
  export _DCTL_KRUN_PREFLIGHT_OK=1
  record_argv_mock podman 0
  # shellcheck disable=SC2329
  _krun_rt_ps() { printf 'ctr123\n'; }
  # shellcheck disable=SC2329
  _extract_gh_token() { printf 'ghp_runtime'; }
  # shellcheck disable=SC2329
  _extract_glab_token() { printf 'glpat_runtime'; }

  run rt_exec "$WORKSPACE_FOLDER" "${WORKSPACE_FOLDER}/.devcontainer/devcontainer.json" -- echo hi
  [ "$status" -eq 0 ]
  assert_argv_call podman 1 exec --env APP_MODE=test --env GH_TOKEN=ghp_runtime --env GITLAB_TOKEN=glpat_runtime ctr123 echo hi
}

@test "rt_ps emits podman ps with label filter and quiet flag" {
  record_argv_mock podman 0 "ctr123"

  run rt_ps --quiet "$WORKSPACE_FOLDER"
  [ "$status" -eq 0 ]
  [ "$output" = "ctr123" ]
  assert_argv_call podman 1 ps --filter "label=devcontainer.local_folder=${WORKSPACE_FOLDER}" -a -q
}

@test "rt_rm removes ids returned by rt_ps" {
  record_argv_mock podman 0
  # shellcheck disable=SC2329
  _krun_rt_ps() { printf 'ctr123\nctr456\n'; }

  run rt_rm "$WORKSPACE_FOLDER"
  [ "$status" -eq 0 ]
  assert_argv_call podman 1 rm -f ctr123 ctr456
}

@test "rt_build emits podman build with containerfile path and gh secret" {
  mkdir -p "${TEST_TMPDIR}/context"
  touch "${TEST_TMPDIR}/context/Containerfile"
  record_argv_mock podman 0
  # shellcheck disable=SC2329
  _extract_gh_token() { printf 'ghp_build'; }

  run rt_build agents "${TEST_TMPDIR}/context"
  [ "$status" -eq 0 ]
  assert_argv_contains_sequence podman 1 build --tag devimg/agents:latest --file "${TEST_TMPDIR}/context/Containerfile"
  assert_mock_called "--secret id=gh_token,src="
  assert_mock_called "${TEST_TMPDIR}/context"
}

@test "rt_image_inspect emits podman image inspect" {
  record_argv_mock podman 0

  run rt_image_inspect devimg/agents:latest
  [ "$status" -eq 0 ]
  assert_argv_call podman 1 image inspect devimg/agents:latest
}

@test "rt_run surfaces missing kvm access preflight failures" {
  unset _DCTL_KRUN_PREFLIGHT_OK
  # The production probe reads /dev/kvm directly, so this test overrides the
  # probe to pin the same failure branch without mutating host device state.
  # shellcheck disable=SC2329
  _doctor_probe_5_kvm_access() { _doctor_check_fail "current user has rw access to /dev/kvm" "missing"; }
  # shellcheck disable=SC2329
  _doctor_probe_5b_kvm_acl() { _doctor_check_pass "/dev/kvm POSIX ACL for current user"; }
  # shellcheck disable=SC2329
  _doctor_probe_1_crun_libkrun() { _doctor_check_pass "crun built with +LIBKRUN feature tag"; }
  # shellcheck disable=SC2329
  _doctor_probe_2_krun_symlink() { _doctor_check_pass "krun symlink resolves to crun"; }
  # shellcheck disable=SC2329
  _doctor_probe_4_libkrun_version() { _doctor_check_pass "libkrun version >= ${MIN_LIBKRUN_VER}"; }

  run rt_run "$WORKSPACE_FOLDER" "${WORKSPACE_FOLDER}/.devcontainer/devcontainer.json"
  [ "$status" -ne 0 ]
  [[ $output == *"krun runtime preflight failed"* ]]
}

@test "rt_run fails preflight when crun lacks +LIBKRUN" {
  unset _DCTL_KRUN_PREFLIGHT_OK
  record_argv_mock crun 0 "crun version 1.20"
  ln -sf "${TEST_TMPDIR}/bin/crun" "${TEST_TMPDIR}/bin/krun"
  create_mock ldconfig 0 "libkrun.so (libc6,x86-64) => /usr/lib64/libkrun.so.1.18.0"
  # shellcheck disable=SC2329
  _doctor_probe_5_kvm_access() { _doctor_check_pass "current user has rw access to /dev/kvm"; }
  # shellcheck disable=SC2329
  _doctor_probe_5b_kvm_acl() { _doctor_check_warn "/dev/kvm POSIX ACL for current user" "warn"; }

  run rt_run "$WORKSPACE_FOLDER" "${WORKSPACE_FOLDER}/.devcontainer/devcontainer.json"
  [ "$status" -ne 0 ]
  [[ $output == *"krun runtime preflight failed"* ]]
  [ "$(cat "${TEST_TMPDIR}/argv/crun.calls")" -eq 1 ]
}

@test "rt_run fails preflight when libkrun is too old" {
  unset _DCTL_KRUN_PREFLIGHT_OK
  record_argv_mock crun 0 "crun version 1.20 +LIBKRUN"
  ln -sf "${TEST_TMPDIR}/bin/crun" "${TEST_TMPDIR}/bin/krun"
  create_mock ldconfig 0 "libkrun.so (libc6,x86-64) => /usr/lib64/libkrun.so.1.17.0"
  # shellcheck disable=SC2329
  _doctor_probe_5_kvm_access() { _doctor_check_pass "current user has rw access to /dev/kvm"; }
  # shellcheck disable=SC2329
  _doctor_probe_5b_kvm_acl() { _doctor_check_warn "/dev/kvm POSIX ACL for current user" "warn"; }

  run rt_run "$WORKSPACE_FOLDER" "${WORKSPACE_FOLDER}/.devcontainer/devcontainer.json"
  [ "$status" -ne 0 ]
  [[ $output == *"krun runtime preflight failed"* ]]
}

@test "missing getfacl only warns and does not fail preflight" {
  unset _DCTL_KRUN_PREFLIGHT_OK
  record_argv_mock crun 0 "crun version 1.20 +LIBKRUN"
  ln -sf "${TEST_TMPDIR}/bin/crun" "${TEST_TMPDIR}/bin/krun"
  create_mock ldconfig 0 "libkrun.so (libc6,x86-64) => /usr/lib64/libkrun.so.1.18.0"
  local old_path="$PATH"
  PATH="${TEST_TMPDIR}/bin:$(sanitized_bin_excluding getfacl)"
  export PATH
  # shellcheck disable=SC2329
  _doctor_probe_5_kvm_access() { _doctor_check_pass "current user has rw access to /dev/kvm"; }
  record_argv_mock podman 0 "ctr123"

  run rt_run "$WORKSPACE_FOLDER" "${WORKSPACE_FOLDER}/.devcontainer/devcontainer.json"
  PATH="$old_path"
  export PATH
  [ "$status" -eq 0 ]
  [ "$output" = "ctr123" ]
}

@test "krun preflight is memoized across rt_run calls until reset" {
  unset _DCTL_KRUN_PREFLIGHT_OK
  record_argv_mock crun 0 "crun version 1.20 +LIBKRUN"
  ln -sf "${TEST_TMPDIR}/bin/crun" "${TEST_TMPDIR}/bin/krun"
  create_mock ldconfig 0 "libkrun.so (libc6,x86-64) => /usr/lib64/libkrun.so.1.18.0"
  record_argv_mock podman 0 "ctr123"
  # shellcheck disable=SC2329
  _doctor_probe_5_kvm_access() { _doctor_check_pass "current user has rw access to /dev/kvm"; }

  rt_run "$WORKSPACE_FOLDER" "${WORKSPACE_FOLDER}/.devcontainer/devcontainer.json" >/dev/null
  rt_run "$WORKSPACE_FOLDER" "${WORKSPACE_FOLDER}/.devcontainer/devcontainer.json" >/dev/null
  [ "$(cat "${TEST_TMPDIR}/argv/crun.calls")" -eq 1 ]

  unset _DCTL_KRUN_PREFLIGHT_OK
  rt_run "$WORKSPACE_FOLDER" "${WORKSPACE_FOLDER}/.devcontainer/devcontainer.json" >/dev/null
  [ "$(cat "${TEST_TMPDIR}/argv/crun.calls")" -eq 2 ]
}

@test "krun http2 workaround hook is a no-op when unset" {
  run _krun_http2_workaround
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "krun http2 workaround hook is a no-op when enabled" {
  export DCTL_KRUN_HTTP2_WORKAROUND=1

  run _krun_http2_workaround
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
