#!/usr/bin/env bats

# bats file_tags=unit

load test_helper

source_auth_runtime() {
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
  __dctl_require _lib/auth/collect_env.sh
  __dctl_require _lib/auth/ephemeral_creds.sh
  __dctl_require _lib/workspace/session_hash.sh
  __dctl_require _lib/workspace/git_worktree.sh
  __dctl_require _lib/workspace/resolve_config.sh
  __dctl_require _lib/term/collect_env.sh
  __dctl_require commands/net/_compose.sh
  __dctl_require commands/ws/_helpers.sh
  __dctl_require commands/ws/up.sh
  __dctl_require commands/ws/down.sh
  __dctl_require runtime/common.sh
  __dctl_require runtime/krun.sh
}

create_auth_fixture() {
  mkdir -p "${WORKSPACE_FOLDER}/.devcontainer"
  cat >"${WORKSPACE_FOLDER}/.devcontainer/devcontainer.json" <<'EOF'
{
  "image": "devimg/agents:latest",
  "remoteEnv": {
    "AUTH_MODE": "test"
  }
}
EOF
}

write_gh_mock() {
  cat >"${TEST_TMPDIR}/bin/gh" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "auth" && "$2" == "status" ]] && exit 0
[[ "$1" == "auth" && "$2" == "token" ]] && printf 'ghp_auth_fixture' && exit 0
exit 1
EOF
  chmod +x "${TEST_TMPDIR}/bin/gh"
}

write_glab_mock() {
  cat >"${TEST_TMPDIR}/bin/glab" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "auth" && "$2" == "status" && "${3:-}" != "--show-token" ]] && exit 0
[[ "$1" == "auth" && "$2" == "status" && "${3:-}" == "--show-token" ]] && printf 'Token: glpat_auth_fixture\n' && exit 0
exit 1
EOF
  chmod +x "${TEST_TMPDIR}/bin/glab"
}

setup() {
  setup_test_fixtures
  export XDG_DATA_HOME="${TEST_TMPDIR}/xdg-data"
  export XDG_CONFIG_HOME="${TEST_TMPDIR}/xdg-config"
  export XDG_CACHE_HOME="${TEST_TMPDIR}/xdg-cache"
  export WORKSPACE_FOLDER="${TEST_TMPDIR}/workspace"
  mkdir -p "${XDG_DATA_HOME}/dctl" "${XDG_CONFIG_HOME}/dctl" "${XDG_CACHE_HOME}/dctl" "$WORKSPACE_FOLDER"
  source_auth_runtime
  create_auth_fixture
  creds_fixture_home >/dev/null
  enable_mocks
  export _DCTL_KRUN_PREFLIGHT_OK=1
  unset GH_TOKEN GITHUB_TOKEN GITLAB_TOKEN TERM COLORTERM 2>/dev/null || true
  # shellcheck disable=SC2329
  run_postcreate() { :; }
  # shellcheck disable=SC2329
  run_poststart() { :; }
}

teardown() {
  teardown_test_fixtures
}

# Token forwarding lives on the exec path in this repo: runtime/krun.sh's
# _krun_collect_exec_env_flags feeds _krun_rt_exec, while rt_run only carries
# config/container env plus the egress allowlist env. These tests pin that split.
@test "cmd_ws_up creates the session dir under DCTL_CACHE_DIR sessions" {
  printf 'claude\n' >"${HOME}/.claude/.credentials.json"
  printf 'codex\n' >"${HOME}/.codex/auth.json"
  printf 'gemini\n' >"${HOME}/.gemini/key.json"
  record_argv_mock podman 0 "ctr123"

  run cmd_ws_up
  [ "$status" -eq 0 ]

  local session_dir
  session_dir="$(workspace_session_dir)"
  [ -d "$session_dir" ]
  [ "$(stat -c '%a' "$session_dir")" = "700" ]
}

@test "cmd_ws_down removes the ephemeral session dir" {
  local session_dir
  session_dir="$(workspace_session_dir)"
  mkdir -p "$session_dir"
  printf 'token\n' >"${session_dir}/tmp"
  # shellcheck disable=SC2329
  rt_ps() { printf 'ctr123\n'; }
  # shellcheck disable=SC2329
  rt_rm() { :; }

  run cmd_ws_down
  [ "$status" -eq 0 ]
  [ ! -e "$session_dir" ]
}

# Pins the empty-ids branch in cmd_ws_down (lib/dctl/commands/ws/down.sh:22-27):
# when no container exists rt_rm must not be invoked, but the ephemeral session
# dir must still be cleaned up.
@test "cmd_ws_down removes the session dir even when no container exists" {
  local session_dir
  session_dir="$(workspace_session_dir)"
  mkdir -p "$session_dir"
  printf 'token\n' >"${session_dir}/tmp"
  # shellcheck disable=SC2329
  rt_ps() { printf ''; }
  # shellcheck disable=SC2329
  rt_rm() {
    printf 'rt_rm should not be called when no containers exist\n' >&2
    return 1
  }

  run cmd_ws_down
  [ "$status" -eq 0 ]
  [ ! -e "$session_dir" ]
}

@test "rt_run mounts copied credential files and never host credential directories" {
  printf 'claude\n' >"${HOME}/.claude/.credentials.json"
  printf 'codex\n' >"${HOME}/.codex/auth.json"
  printf 'gemini\n' >"${HOME}/.gemini/key.json"
  printf 'oauth_token: ghp_cfg\n' >"${HOME}/.config/gh/hosts.yml"
  record_argv_mock podman 0 "ctr123"

  run cmd_ws_up
  [ "$status" -eq 0 ]
  assert_mock_not_called "source=${HOME}/.config/gh"
  assert_mock_not_called "source=${HOME}/.claude,target=${HOME}/.claude"
  assert_mock_not_called "source=${HOME}/.codex,target=${HOME}/.codex"
  assert_mock_not_called "source=${HOME}/.gemini,target=${HOME}/.gemini"

  local session_dir
  session_dir="$(workspace_session_dir)"
  assert_mock_called "source=${session_dir}/claude/.credentials.json"
  assert_mock_called "source=${session_dir}/codex/auth.json"
  assert_mock_called "source=${session_dir}/gemini/key.json"
}

@test "devcontainer_exec forwards GH_TOKEN and GITLAB_TOKEN on podman exec" {
  record_argv_mock podman 0
  write_gh_mock
  write_glab_mock
  # shellcheck disable=SC2329
  _krun_rt_ps() { printf 'ctr123\n'; }

  run devcontainer_exec -- echo hi
  [ "$status" -eq 0 ]
  assert_mock_called "--env GH_TOKEN=ghp_auth_fixture"
  assert_mock_called "--env GITLAB_TOKEN=glpat_auth_fixture"
  assert_argv_contains_sequence podman 1 exec --env AUTH_MODE=test
}

@test "devcontainer_exec omits auth token env flags when no CLI is configured" {
  record_argv_mock podman 0
  local old_path="$PATH"
  PATH="${TEST_TMPDIR}/bin:$(sanitized_bin_excluding gh glab)"
  export PATH
  # shellcheck disable=SC2329
  _krun_rt_ps() { printf 'ctr123\n'; }

  run devcontainer_exec -- echo hi
  PATH="$old_path"
  export PATH
  [ "$status" -eq 0 ]
  assert_mock_not_called "GH_TOKEN="
  assert_mock_not_called "GITLAB_TOKEN="
}
