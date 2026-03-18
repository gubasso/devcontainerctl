#!/usr/bin/env bats

# bats file_tags=unit

load test_helper

source_auth() {
  local repo_root
  repo_root="${BATS_TEST_DIRNAME}/.."
  readonly DCTL_LIB_DIR="${repo_root}/lib/dctl"
  set -euo pipefail
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/common.sh"
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/auth.sh"
}

# PATH with mock dir + system dirs (for tests needing mocks)
_mock_path() {
  printf '%s:/usr/bin:/bin' "${TEST_TMPDIR}/bin"
}

# Create a sysbin dir with essential tools but without gh/glab
_setup_sysbin() {
  local sysbin="${TEST_TMPDIR}/sysbin"
  mkdir -p "$sysbin"
  local cmd
  for cmd in bash printf awk grep cat mkdir chmod rm; do
    if command -v "$cmd" >/dev/null 2>&1; then
      ln -sf "$(command -v "$cmd")" "${sysbin}/${cmd}"
    fi
  done
}

# PATH without gh/glab — uses curated sysbin
_no_cli_path() {
  printf '%s:%s/sysbin' "${TEST_TMPDIR}/bin" "$TEST_TMPDIR"
}

setup() {
  setup_test_fixtures
  _setup_sysbin
  unset GH_TOKEN GITHUB_TOKEN GITLAB_TOKEN
  source_auth
}

teardown() {
  teardown_test_fixtures
}

# --- collect_auth_env ---

@test "collect_auth_env returns empty when no CLIs available" {
  local -a args
  PATH="$(_no_cli_path)" collect_auth_env args
  [ "${#args[@]}" -eq 0 ]
}

@test "collect_auth_env includes GH_TOKEN when gh authenticated" {
  enable_mocks
  cat >"${TEST_TMPDIR}/bin/gh" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == "auth" && "$2" == "status" ]] && exit 0
[[ "$1" == "auth" && "$2" == "token" ]] && printf 'ghp_test123' && exit 0
exit 1
MOCK
  chmod +x "${TEST_TMPDIR}/bin/gh"

  local -a args
  PATH="$(_mock_path)" collect_auth_env args
  [[ "${args[*]}" == *"--remote-env GH_TOKEN=ghp_test123"* ]]
}

@test "collect_auth_env includes GITLAB_TOKEN when glab authenticated" {
  enable_mocks
  cat >"${TEST_TMPDIR}/bin/glab" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == "auth" && "$2" == "status" && "$3" != "--show-token" ]] && exit 0
[[ "$1" == "auth" && "$2" == "status" && "$3" == "--show-token" ]] && printf 'Token: mock_glab_tok456\n' && exit 0
exit 1
MOCK
  chmod +x "${TEST_TMPDIR}/bin/glab"

  local -a args
  PATH="$(_mock_path)" collect_auth_env args
  [[ "${args[*]}" == *"--remote-env GITLAB_TOKEN=mock_glab_tok456"* ]]
}

@test "collect_auth_env includes both tokens when both CLIs authenticated" {
  enable_mocks
  cat >"${TEST_TMPDIR}/bin/gh" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == "auth" && "$2" == "status" ]] && exit 0
[[ "$1" == "auth" && "$2" == "token" ]] && printf 'ghp_both123' && exit 0
exit 1
MOCK
  chmod +x "${TEST_TMPDIR}/bin/gh"

  cat >"${TEST_TMPDIR}/bin/glab" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == "auth" && "$2" == "status" && "$3" != "--show-token" ]] && exit 0
[[ "$1" == "auth" && "$2" == "status" && "$3" == "--show-token" ]] && printf 'Token: mock_glab_tok789\n' && exit 0
exit 1
MOCK
  chmod +x "${TEST_TMPDIR}/bin/glab"

  local -a args
  PATH="$(_mock_path)" collect_auth_env args
  [[ "${args[*]}" == *"--remote-env GH_TOKEN=ghp_both123"* ]]
  [[ "${args[*]}" == *"--remote-env GITLAB_TOKEN=mock_glab_tok789"* ]]
}

@test "collect_auth_env suppresses warnings on stderr" {
  local -a args
  local stderr_output
  stderr_output=$(PATH="$(_no_cli_path)" collect_auth_env args 2>&1 >/dev/null)
  [ "$stderr_output" = "" ]
}

# --- env var short-circuit ---

@test "_extract_gh_token returns GH_TOKEN env var" {
  # shellcheck disable=SC2030
  GH_TOKEN="ghp_from_env"
  run _extract_gh_token
  [ "$status" -eq 0 ]
  [ "$output" = "ghp_from_env" ]
}

@test "_extract_gh_token returns GITHUB_TOKEN when GH_TOKEN unset" {
  # shellcheck disable=SC2030
  GITHUB_TOKEN="ghp_github_env"
  run _extract_gh_token
  [ "$status" -eq 0 ]
  [ "$output" = "ghp_github_env" ]
}

@test "_extract_gh_token prefers GH_TOKEN over GITHUB_TOKEN" {
  # shellcheck disable=SC2030,SC2031
  export GH_TOKEN="ghp_primary"
  # shellcheck disable=SC2031
  export GITHUB_TOKEN="ghp_secondary"
  run _extract_gh_token
  [ "$status" -eq 0 ]
  [ "$output" = "ghp_primary" ]
}

@test "_extract_glab_token returns GITLAB_TOKEN env var" {
  # shellcheck disable=SC2030
  GITLAB_TOKEN="glpat_from_env"
  run _extract_glab_token
  [ "$status" -eq 0 ]
  [ "$output" = "glpat_from_env" ]
}

@test "collect_auth_env uses env vars, no CLIs needed" {
  # shellcheck disable=SC2030,SC2031
  export GH_TOKEN="ghp_envonly"
  # shellcheck disable=SC2031
  export GITLAB_TOKEN="glpat_envonly"
  local -a args
  PATH="$(_no_cli_path)" collect_auth_env args
  [[ "${args[*]}" == *"--remote-env GH_TOKEN=ghp_envonly"* ]]
  [[ "${args[*]}" == *"--remote-env GITLAB_TOKEN=glpat_envonly"* ]]
}

@test "_extract_gh_token prefers env var over CLI" {
  enable_mocks
  cat >"${TEST_TMPDIR}/bin/gh" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == "auth" && "$2" == "status" ]] && exit 0
[[ "$1" == "auth" && "$2" == "token" ]] && printf 'ghp_from_cli' && exit 0
exit 1
MOCK
  chmod +x "${TEST_TMPDIR}/bin/gh"

  # shellcheck disable=SC2031
  export GH_TOKEN="ghp_from_env"
  local result
  result=$(PATH="$(_mock_path)" _extract_gh_token)
  [ "$result" = "ghp_from_env" ]
}

@test "_extract_gh_token falls back to CLI when no env vars" {
  enable_mocks
  cat >"${TEST_TMPDIR}/bin/gh" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == "auth" && "$2" == "status" ]] && exit 0
[[ "$1" == "auth" && "$2" == "token" ]] && printf 'ghp_cli_fallback' && exit 0
exit 1
MOCK
  chmod +x "${TEST_TMPDIR}/bin/gh"

  local result
  result=$(PATH="$(_mock_path)" _extract_gh_token)
  [ "$result" = "ghp_cli_fallback" ]
}
