#!/usr/bin/env bats

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
  for cmd in bash printf awk grep stat cat mkdir chmod rm; do
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
  export _TOKEN_ENV_FILE="${TEST_TMPDIR}/tokens.env"
  _setup_sysbin
  source_auth
}

teardown() {
  teardown_test_fixtures
}

# --- gh token extraction ---

@test "gh not installed warns and writes empty GH_TOKEN" {
  PATH="$(_no_cli_path)" run cmd_auth_init_tokens
  [ "$status" -eq 0 ]
  [[ "$output" == *"gh CLI not found"* ]]
  grep -q '^GH_TOKEN=$' "$_TOKEN_ENV_FILE"
}

@test "gh not authenticated warns" {
  enable_mocks
  create_mock gh 1

  PATH="$(_mock_path)" run cmd_auth_init_tokens
  [ "$status" -eq 0 ]
  [[ "$output" == *"gh not authenticated"* ]]
  grep -q '^GH_TOKEN=$' "$_TOKEN_ENV_FILE"
}

@test "gh authenticated extracts token" {
  enable_mocks
  cat >"${TEST_TMPDIR}/bin/gh" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "auth" && "$2" == "status" ]]; then
  exit 0
elif [[ "$1" == "auth" && "$2" == "token" ]]; then
  printf 'ghp_test123'
  exit 0
fi
exit 1
MOCK
  chmod +x "${TEST_TMPDIR}/bin/gh"

  PATH="$(_mock_path)" run cmd_auth_init_tokens
  [ "$status" -eq 0 ]
  [[ "$output" == *"GitHub token extracted"* ]]
  grep -q '^GH_TOKEN=ghp_test123$' "$_TOKEN_ENV_FILE"
}

# --- glab token extraction ---

@test "glab not installed warns and writes empty GITLAB_TOKEN" {
  PATH="$(_no_cli_path)" run cmd_auth_init_tokens
  [ "$status" -eq 0 ]
  [[ "$output" == *"glab CLI not found"* ]]
  grep -q '^GITLAB_TOKEN=$' "$_TOKEN_ENV_FILE"
}

@test "glab not authenticated warns" {
  enable_mocks
  create_mock glab 1

  PATH="$(_mock_path)" run cmd_auth_init_tokens
  [ "$status" -eq 0 ]
  [[ "$output" == *"glab not authenticated"* ]]
  grep -q '^GITLAB_TOKEN=$' "$_TOKEN_ENV_FILE"
}

@test "glab authenticated extracts token" {
  enable_mocks
  cat >"${TEST_TMPDIR}/bin/glab" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "auth" && "$2" == "status" && "$3" != "--show-token" ]]; then
  exit 0
elif [[ "$1" == "auth" && "$2" == "status" && "$3" == "--show-token" ]]; then
  printf 'Token: mock_glab_tok456\n'
  exit 0
fi
exit 1
MOCK
  chmod +x "${TEST_TMPDIR}/bin/glab"

  PATH="$(_mock_path)" run cmd_auth_init_tokens
  [ "$status" -eq 0 ]
  [[ "$output" == *"GitLab token extracted"* ]]
  grep -q '^GITLAB_TOKEN=mock_glab_tok456$' "$_TOKEN_ENV_FILE"
}

# --- combined scenarios ---

@test "both missing warns no tokens extracted" {
  PATH="$(_no_cli_path)" run cmd_auth_init_tokens
  [ "$status" -eq 0 ]
  [[ "$output" == *"No tokens extracted"* ]]
  grep -q '^GH_TOKEN=$' "$_TOKEN_ENV_FILE"
  grep -q '^GITLAB_TOKEN=$' "$_TOKEN_ENV_FILE"
}

@test "both present writes both tokens" {
  enable_mocks
  cat >"${TEST_TMPDIR}/bin/gh" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "auth" && "$2" == "status" ]]; then exit 0; fi
if [[ "$1" == "auth" && "$2" == "token" ]]; then printf 'ghp_both123'; exit 0; fi
exit 1
MOCK
  chmod +x "${TEST_TMPDIR}/bin/gh"

  cat >"${TEST_TMPDIR}/bin/glab" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "auth" && "$2" == "status" && "$3" != "--show-token" ]]; then exit 0; fi
if [[ "$1" == "auth" && "$2" == "status" && "$3" == "--show-token" ]]; then printf 'Token: mock_glab_tok789\n'; exit 0; fi
exit 1
MOCK
  chmod +x "${TEST_TMPDIR}/bin/glab"

  PATH="$(_mock_path)" run cmd_auth_init_tokens
  [ "$status" -eq 0 ]
  [[ "$output" == *"GitHub token extracted"* ]]
  [[ "$output" == *"GitLab token extracted"* ]]
  grep -q '^GH_TOKEN=ghp_both123$' "$_TOKEN_ENV_FILE"
  grep -q '^GITLAB_TOKEN=mock_glab_tok789$' "$_TOKEN_ENV_FILE"
}

@test "env file permissions are 0600" {
  PATH="$(_no_cli_path)" run cmd_auth_init_tokens
  [ "$status" -eq 0 ]
  local perms
  perms=$(stat -c '%a' "$_TOKEN_ENV_FILE")
  [ "$perms" = "600" ]
}

@test "always exits 0 even when both fail" {
  PATH="$(_no_cli_path)" run cmd_auth_init_tokens
  [ "$status" -eq 0 ]
}
