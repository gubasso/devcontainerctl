#!/usr/bin/env bats

# bats file_tags=unit

load test_helper

source_providers() {
  local repo_root
  repo_root="${BATS_TEST_DIRNAME}/.."
  readonly DCTL_LIB_DIR="${repo_root}/lib/dctl"
  set -euo pipefail
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/common.sh"
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/providers.sh"
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/config.sh"
}

# Register the fixture workspace against a manifest declaring the given
# providers block (raw YAML lines, already indented under `providers:`).
_write_manifest_fixture() {
  local providers_yaml="${1:-}"

  mkdir -p "${DCTL_CONFIG_DIR}/devcontainer"
  cat >"${DCTL_CONFIG_DIR}/projects.yaml" <<EOF
workspace:
  devcontainer-manifest: testman
EOF
  {
    printf 'layers:\n  - base\n'
    if [[ -n $providers_yaml ]]; then
      printf 'providers:\n%s\n' "$providers_yaml"
    fi
  } >"${DCTL_CONFIG_DIR}/devcontainer/testman.yaml"
}

_write_provider_mock() {
  local name="$1"
  local exit_code="$2"
  local stdout="${3:-}"

  cat >"${TEST_TMPDIR}/bin/${name}" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$(basename "\$0") \$*" >>"${TEST_TMPDIR}/mock_calls.log"
if [[ -n '${stdout}' ]]; then
  printf '%s\n' '${stdout}'
fi
exit ${exit_code}
MOCK
  chmod +x "${TEST_TMPDIR}/bin/${name}"
}

setup() {
  setup_test_fixtures
  export WORKSPACE_FOLDER="${TEST_TMPDIR}/workspace"
  mkdir -p "$WORKSPACE_FOLDER"
  export DCTL_CONFIG_DIR="${TEST_TMPDIR}/config"
  mkdir -p "$DCTL_CONFIG_DIR"
  # Validate against the repo's schemas, never whatever this host has deployed.
  export DCTL_SCHEMAS_DIR="${BATS_TEST_DIRNAME}/../schemas"
  unset DCTL_CLI_CONFIG DCTL_CONFIG
  source_providers
}

teardown() {
  teardown_test_fixtures
}

# --- list_project_providers ---

@test "list_project_providers is empty without a registered manifest" {
  run list_project_providers
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "list_project_providers is empty when the manifest declares none" {
  _write_manifest_fixture ""
  run list_project_providers
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "list_project_providers reads name and required in manifest order" {
  _write_manifest_fixture "  - name: prov-a
  - name: prov-b
    required: false"
  run list_project_providers
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(printf 'prov-a\ttrue')" ]
  [ "${lines[1]}" = "$(printf 'prov-b\tfalse')" ]
}

@test "an explicit config bypasses providers with the manifest" {
  _write_manifest_fixture "  - name: prov-a"
  export DCTL_CLI_CONFIG="${TEST_TMPDIR}/some.json"
  run list_project_providers
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

# --- collect_provider_args ---

@test "collect_provider_args composes mounts and remoteEnv into CLI args" {
  _write_manifest_fixture "  - name: prov-a"
  _write_provider_mock prov-a 0 '{"mounts":["type=bind,source=/tmp/x,target=/tmp/x"],"remoteEnv":{"FOO":"bar"}}'
  enable_mocks

  local -a args
  collect_provider_args prepare args
  [ "${args[0]}" = "--mount" ]
  [ "${args[1]}" = "type=bind,source=/tmp/x,target=/tmp/x" ]
  [ "${args[2]}" = "--remote-env" ]
  [ "${args[3]}" = "FOO=bar" ]
  assert_mock_called "prov-a prepare --workspace ${WORKSPACE_FOLDER} --project workspace"
}

@test "empty provider stdout contributes nothing" {
  _write_manifest_fixture "  - name: prov-a"
  _write_provider_mock prov-a 0 ""
  enable_mocks

  local -a args
  collect_provider_args prepare args
  [ "${#args[@]}" -eq 0 ]
}

@test "a required provider missing from PATH aborts" {
  _write_manifest_fixture "  - name: prov-gone"
  enable_mocks

  run collect_provider_args prepare _unused
  [ "$status" -eq 1 ]
  [[ $output == *"Required provider 'prov-gone' not found"* ]]
}

@test "an optional provider missing from PATH degrades to a warning" {
  _write_manifest_fixture "  - name: prov-gone
    required: false"
  enable_mocks

  local -a args
  collect_provider_args prepare args
  [ "${#args[@]}" -eq 0 ]
}

@test "a required provider failure aborts; an optional one is skipped" {
  _write_manifest_fixture "  - name: prov-a"
  _write_provider_mock prov-a 1 ""
  enable_mocks

  run collect_provider_args prepare _unused
  [ "$status" -eq 1 ]
  [[ $output == *"Required provider 'prov-a' failed during 'prepare'"* ]]

  _write_manifest_fixture "  - name: prov-a
    required: false"
  local -a args
  collect_provider_args prepare args
  [ "${#args[@]}" -eq 0 ]
}

@test "malformed provider JSON aborts a required provider" {
  _write_manifest_fixture "  - name: prov-a"
  _write_provider_mock prov-a 0 'not-json'
  enable_mocks

  run collect_provider_args prepare _unused
  [ "$status" -eq 1 ]
  [[ $output == *"malformed"* ]]
}

@test "false or null field values are malformed, not empty" {
  # jq's // treats false/null as absent; the validator must not.
  _write_manifest_fixture "  - name: prov-a"
  _write_provider_mock prov-a 0 '{"mounts":false}'
  enable_mocks

  run collect_provider_args prepare _unused
  [ "$status" -eq 1 ]
  [[ $output == *"malformed"* ]]

  _write_provider_mock prov-a 0 '{"remoteEnv":null}'
  run collect_provider_args prepare _unused
  [ "$status" -eq 1 ]
  [[ $output == *"malformed"* ]]
}

@test "unknown top-level keys are malformed" {
  _write_manifest_fixture "  - name: prov-a"
  _write_provider_mock prov-a 0 '{"mountz":["type=bind,source=/tmp/x,target=/tmp/x"]}'
  enable_mocks

  run collect_provider_args prepare _unused
  [ "$status" -eq 1 ]
  [[ $output == *"malformed"* ]]
}

@test "a well-formed answer with a non-string mount is malformed" {
  _write_manifest_fixture "  - name: prov-a"
  _write_provider_mock prov-a 0 '{"mounts":[42]}'
  enable_mocks

  run collect_provider_args prepare _unused
  [ "$status" -eq 1 ]
  [[ $output == *"malformed"* ]]
}

# --- provider_release_all ---

@test "provider_release_all invokes release and never fails" {
  _write_manifest_fixture "  - name: prov-a
  - name: prov-fails"
  _write_provider_mock prov-a 0 ""
  _write_provider_mock prov-fails 1 ""
  enable_mocks

  run provider_release_all
  [ "$status" -eq 0 ]
  assert_mock_called "prov-a release --workspace ${WORKSPACE_FOLDER} --project workspace"
  assert_mock_called "prov-fails release --workspace ${WORKSPACE_FOLDER} --project workspace"
}

# --- run_provider_checks (test.sh) ---

source_test_module() {
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/test.sh"
}

@test "run_provider_checks fails on a failing required provider" {
  _write_manifest_fixture "  - name: prov-a"
  _write_provider_mock prov-a 1 ""
  enable_mocks
  source_test_module

  run run_provider_checks
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL"* ]]
}

@test "run_provider_checks degrades a failing optional provider to a warning" {
  _write_manifest_fixture "  - name: prov-a
    required: false"
  _write_provider_mock prov-a 1 ""
  enable_mocks
  source_test_module

  run run_provider_checks
  [ "$status" -eq 0 ]
  [[ $output == *"continuing degraded"* ]]
  [[ $output != *"FAIL"* ]]
}

# --- cmd_test smoke lifecycle (attach failure, release gating) ---

_setup_smoke_fixture() {
  # The registry manifest wins config resolution, so the manifest's one layer
  # must exist for generation to succeed (no image field -> image build is
  # skipped with a warning).
  mkdir -p "${DCTL_CONFIG_DIR}/devcontainer/base"
  printf '{}\n' >"${DCTL_CONFIG_DIR}/devcontainer/base/devcontainer.json"
}

@test "cmd_test fails the attach row but still cleans up and releases" {
  _write_manifest_fixture "  - name: prov-a"
  _setup_smoke_fixture
  # Provider: fine on check/prepare/release, fails on attach.
  cat >"${TEST_TMPDIR}/bin/prov-a" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "prov-a \$*" >>"${TEST_TMPDIR}/mock_calls.log"
[[ \$1 == attach ]] && exit 1
exit 0
MOCK
  chmod +x "${TEST_TMPDIR}/bin/prov-a"
  create_mock docker 0 ""
  create_mock devcontainer 0 ""
  enable_mocks
  source_test_module

  run cmd_test
  [ "$status" -ne 0 ]
  [[ $output == *"Provider attach phase"* ]]
  # Cleanup ran and, with no containers left, release was invoked.
  assert_mock_called "prov-a release --workspace ${WORKSPACE_FOLDER} --project workspace"
}

@test "cmd_test passes attach args through to devcontainer exec intact" {
  _write_manifest_fixture "  - name: prov-a"
  _setup_smoke_fixture
  _write_provider_mock prov-a 0 '{"mounts":["type=bind,source=/tmp/x,target=/tmp/x"],"remoteEnv":{"FOO":"bar baz"}}'
  create_mock docker 0 ""
  create_mock devcontainer 0 ""
  enable_mocks
  source_test_module

  run cmd_test
  [ "$status" -eq 0 ]
  grep -q -- "--mount type=bind,source=/tmp/x,target=/tmp/x --remote-env FOO=bar baz" "${TEST_TMPDIR}/mock_calls.log"
}

@test "cmd_test skips release while workspace containers remain" {
  _write_manifest_fixture "  - name: prov-a"
  _setup_smoke_fixture
  _write_provider_mock prov-a 0 ""
  # docker ps keeps reporting a container, so cleanup cannot converge.
  create_mock docker 0 "container123"
  create_mock devcontainer 0 ""
  enable_mocks
  source_test_module

  run cmd_test
  [[ $output == *"skipping provider release"* ]]
  # release must NOT have run
  assert_mock_not_called "prov-a release"
}

# --- manifest validation ---

@test "manifest validation rejects a providers entry without a name" {
  _write_manifest_fixture "  - required: true"
  run discover_config_layers testman
  [ "$status" -eq 1 ]
  [[ $output == *"provider"* ]] || [[ $output == *"Schema validation failed"* ]]
}

@test "manifest validation rejects unknown provider keys" {
  _write_manifest_fixture "  - name: prov-a
    extra: nope"
  run discover_config_layers testman
  [ "$status" -eq 1 ]
  [[ $output == *"provider"* ]] || [[ $output == *"Schema validation failed"* ]]
}
