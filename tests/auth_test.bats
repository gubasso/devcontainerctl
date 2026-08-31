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

# Create a sysbin dir with essential tools but without gh/glab/forge-seed
_setup_sysbin() {
  local sysbin="${TEST_TMPDIR}/sysbin"
  mkdir -p "$sysbin"
  local cmd
  for cmd in bash printf awk grep cat mkdir chmod rm cp sort id dirname basename git; do
    if command -v "$cmd" >/dev/null 2>&1; then
      ln -sf "$(command -v "$cmd")" "${sysbin}/${cmd}"
    fi
  done
}

# PATH without gh/glab/forge-seed — uses curated sysbin
_no_cli_path() {
  printf '%s:%s/sysbin' "${TEST_TMPDIR}/bin" "$TEST_TMPDIR"
}

# forge-seed mock: records the call, materializes the scope dir, honours
# --print-dir. The seeding logic itself lives in nix-secrets and is not
# dctl's to test — dctl's contract is the call, the mount, and the env.
_write_forge_seed_mock() {
  cat >"${TEST_TMPDIR}/bin/forge-seed" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "forge-seed \$*" >>"${TEST_TMPDIR}/mock_calls.log"
scope=""
print_dir=false
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --scope) scope="\$2"; shift 2 ;;
    --print-dir) print_dir=true; shift ;;
    *) shift ;;
  esac
done
dir="${TEST_TMPDIR}/rt/\${scope}"
mkdir -p "\$dir/gh" "\$dir/glab-cli"
[[ \$print_dir == true ]] && printf '%s\n' "\$dir"
exit 0
MOCK
  chmod +x "${TEST_TMPDIR}/bin/forge-seed"
}

setup() {
  setup_test_fixtures
  _setup_sysbin
  export WORKSPACE_FOLDER="${TEST_TMPDIR}/workspace"
  mkdir -p "$WORKSPACE_FOLDER"
  unset GH_TOKEN GITHUB_TOKEN GITLAB_TOKEN SSH_AUTH_SOCK
  source_auth
}

teardown() {
  teardown_test_fixtures
}

# --- collect_forge_auth_env / collect_forge_auth_mounts ---

@test "collect_forge_auth_env never emits a token" {
  _write_forge_seed_mock
  enable_mocks
  # Even with tokens sitting in the host environment, only paths may travel.
  export GH_TOKEN="ghp_hostside123"
  export GITLAB_TOKEN="glpat_hostside456"

  local -a args
  collect_forge_auth_env args
  [[ ${args[*]} == *"--remote-env GH_CONFIG_DIR=/run/forge-auth/gh"* ]]
  [[ ${args[*]} == *"--remote-env GLAB_CONFIG_DIR=/run/forge-auth/glab-cli"* ]]
  [[ ${args[*]} != *"GH_TOKEN="* ]]
  [[ ${args[*]} != *"GITLAB_TOKEN="* ]]
  [[ ${args[*]} != *"ghp_hostside123"* ]]
  [[ ${args[*]} != *"glpat_hostside456"* ]]
}

@test "collect_forge_auth_mounts binds the seed dir at /run/forge-auth" {
  _write_forge_seed_mock
  enable_mocks

  local -a mounts
  collect_forge_auth_mounts mounts
  [ "${mounts[0]}" = "--mount" ]
  [ "${mounts[1]}" = "type=bind,source=${TEST_TMPDIR}/rt/workspace,target=/run/forge-auth" ]
  assert_mock_called "forge-seed --scope workspace --print-dir"
}

@test "collect_forge_auth_env re-seeds on every call" {
  _write_forge_seed_mock
  enable_mocks

  local -a args
  collect_forge_auth_env args
  collect_forge_auth_env args
  [ "$(grep -c "forge-seed --scope workspace" "${TEST_TMPDIR}/mock_calls.log")" -eq 2 ]
}

@test "collect_forge_auth_mounts refuses an empty or dangling seeder answer" {
  # forge-seed may exit 0 with no output (its warn-don't-fail contract);
  # an empty bind source would fail devcontainer up instead of degrading.
  cat >"${TEST_TMPDIR}/bin/forge-seed" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
  chmod +x "${TEST_TMPDIR}/bin/forge-seed"
  enable_mocks

  local -a mounts
  collect_forge_auth_mounts mounts
  [[ ${mounts[*]} != *"forge-auth"* ]]

  # Non-empty answer naming a directory that does not exist is refused too
  cat >"${TEST_TMPDIR}/bin/forge-seed" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "${TEST_TMPDIR}/does-not-exist"
exit 0
MOCK
  chmod +x "${TEST_TMPDIR}/bin/forge-seed"
  collect_forge_auth_mounts mounts
  [[ ${mounts[*]} != *"forge-auth"* ]]
}

@test "collectors degrade when forge-seed is absent" {
  local -a args mounts
  PATH="$(_no_cli_path)" collect_forge_auth_env args
  PATH="$(_no_cli_path)" collect_forge_auth_mounts mounts
  [[ ${args[*]} == *"GH_CONFIG_DIR=/run/forge-auth/gh"* ]]
  [[ ${args[*]} == *"GLAB_CONFIG_DIR=/run/forge-auth/glab-cli"* ]]
  [[ ${mounts[*]} != *"forge-auth"* ]]
}

@test "ssh agent forwarded only when the socket exists" {
  _write_forge_seed_mock
  enable_mocks

  local -a args mounts

  # unset -> neither the var nor the mount
  collect_forge_auth_env args
  collect_forge_auth_mounts mounts
  [[ ${args[*]} != *"SSH_AUTH_SOCK"* ]]
  [[ ${mounts[*]} != *"ssh-agent.sock"* ]]

  # regular file -> refused (the -S guard)
  touch "${TEST_TMPDIR}/not-a-socket"
  SSH_AUTH_SOCK="${TEST_TMPDIR}/not-a-socket" collect_forge_auth_env args
  SSH_AUTH_SOCK="${TEST_TMPDIR}/not-a-socket" collect_forge_auth_mounts mounts
  [[ ${args[*]} != *"SSH_AUTH_SOCK"* ]]
  [[ ${mounts[*]} != *"ssh-agent.sock"* ]]

  # real socket -> both
  command -v python3 >/dev/null 2>&1 || skip "python3 unavailable to create a socket"
  python3 -c "import socket; socket.socket(socket.AF_UNIX).bind('${TEST_TMPDIR}/agent.sock')"
  SSH_AUTH_SOCK="${TEST_TMPDIR}/agent.sock" collect_forge_auth_env args
  SSH_AUTH_SOCK="${TEST_TMPDIR}/agent.sock" collect_forge_auth_mounts mounts
  [[ ${args[*]} == *"--remote-env SSH_AUTH_SOCK=/run/dctl/ssh-agent.sock"* ]]
  [[ ${mounts[*]} == *"type=bind,source=${TEST_TMPDIR}/agent.sock,target=/run/dctl/ssh-agent.sock"* ]]
}

# --- token extraction (image build only) ---

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
