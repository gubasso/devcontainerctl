#!/usr/bin/env bats

load test_helper

source_dctl_functions() {
  local repo_root
  repo_root="${BATS_TEST_DIRNAME}/.."
  readonly DCTL_LIB_DIR="${repo_root}/lib/dctl"
  set -euo pipefail
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/common.sh"
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/workspace.sh"
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/image.sh"
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/init.sh"
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/test.sh"
}

create_template_fixture() {
  local name="$1"
  local image="$2"
  mkdir -p "${XDG_DATA_HOME}/dctl/templates/${name}"
  printf '{\n  "image": "%s"\n}\n' "$image" >"${XDG_DATA_HOME}/dctl/templates/${name}/devcontainer.json"
}

create_image_fixture() {
  local name="$1"
  mkdir -p "${XDG_DATA_HOME}/dctl/images/${name}"
  touch "${XDG_DATA_HOME}/dctl/images/${name}/Dockerfile"
}

setup() {
  setup_test_fixtures
  export XDG_DATA_HOME="${TEST_TMPDIR}/xdg-data"
  export WORKSPACE_FOLDER="${TEST_TMPDIR}/workspace"
  mkdir -p "${XDG_DATA_HOME}/dctl/images" "$WORKSPACE_FOLDER"
  source_dctl_functions
  # shellcheck disable=SC2329
  workspace_path() { printf '%s\n' "$WORKSPACE_FOLDER"; }
  # shellcheck disable=SC2329
  workspace_devcontainer_dir() { printf '%s/.devcontainer\n' "$WORKSPACE_FOLDER"; }
  # shellcheck disable=SC2329
  workspace_devcontainer_file() { printf '%s/.devcontainer/devcontainer.json\n' "$WORKSPACE_FOLDER"; }
  unset TERM COLORTERM TERM_PROGRAM TERM_PROGRAM_VERSION 2>/dev/null || true
}

teardown() {
  teardown_test_fixtures
}

@test "workspace_label_filter formats docker filter correctly" {
  run workspace_label_filter
  [ "$status" -eq 0 ]
  [ "$output" = "label=devcontainer.local_folder=${WORKSPACE_FOLDER}" ]
}

@test "list_workspace_containers uses docker ps -a" {
  enable_mocks
  create_mock docker 0 "abc123"

  run list_workspace_containers
  [ "$status" -eq 0 ]
  [ "$output" = "abc123" ]
  assert_mock_called "docker ps -a"
}

@test "list_running_workspace_containers uses docker ps without -a" {
  enable_mocks
  create_mock docker 0 "def456"

  run list_running_workspace_containers
  [ "$status" -eq 0 ]
  [ "$output" = "def456" ]
  assert_mock_called "docker ps --filter"
  assert_mock_not_called "docker ps -a"
}

@test "ensure_workspace_container_running skips startup when container is running" {
  enable_mocks
  create_mock docker 0 "running123"
  create_mock devcontainer 0 ""

  cmd_workspace_up() { echo "CMD_WORKSPACE_UP_CALLED" >>"${TEST_TMPDIR}/mock_calls.log"; }

  run ensure_workspace_container_running
  [ "$status" -eq 0 ]
  assert_mock_not_called "CMD_WORKSPACE_UP_CALLED"
}

@test "ensure_workspace_container_running starts container when needed" {
  enable_mocks
  create_mock docker 0 ""
  create_mock devcontainer 0 ""

  run ensure_workspace_container_running
  [ "$status" -eq 0 ]
  assert_mock_called "devcontainer up"
}

@test "cmd_workspace_exec defaults to bash" {
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""

  run cmd_workspace_exec
  [ "$status" -eq 0 ]
  assert_mock_called "devcontainer exec --workspace-folder ${WORKSPACE_FOLDER} bash"
}

@test "cmd_workspace_exec passes args through" {
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""

  run cmd_workspace_exec -- id
  [ "$status" -eq 0 ]
  assert_mock_called "devcontainer exec --workspace-folder ${WORKSPACE_FOLDER} id"
}

@test "cmd_workspace_shell runs commands in a login shell" {
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""

  run cmd_workspace_shell codex
  [ "$status" -eq 0 ]
  assert_mock_called "devcontainer exec --workspace-folder ${WORKSPACE_FOLDER} bash -lic codex"
}

@test "cmd_workspace_run requires a command" {
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""

  run cmd_workspace_run
  [ "$status" -ne 0 ]
  [[ "$output" == *"run requires a command"* ]]
}

@test "cmd_workspace_run wraps commands with bash -lc" {
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""

  run cmd_workspace_run -- pytest -q
  [ "$status" -eq 0 ]
  assert_mock_called "devcontainer exec --workspace-folder ${WORKSPACE_FOLDER} bash -lc pytest -q"
}

@test "cmd_workspace_status does not auto-start a container" {
  enable_mocks
  create_mock docker 0 "abc123"

  run cmd_workspace_status
  [ "$status" -eq 0 ]
  assert_mock_not_called "devcontainer up"
}

@test "cmd_workspace_down warns when nothing matches" {
  enable_mocks
  create_mock docker 0 ""

  run cmd_workspace_down
  [ "$status" -eq 0 ]
  [[ "$output" == *"No devcontainer to remove"* ]]
}

@test "cmd_workspace_up passes args to devcontainer up" {
  enable_mocks
  create_mock devcontainer 0 ""

  run cmd_workspace_up -- --build-no-cache
  [ "$status" -eq 0 ]
  assert_mock_called "devcontainer up --workspace-folder ${WORKSPACE_FOLDER} --build-no-cache"
}

@test "cmd_workspace_reup adds remove-existing-container" {
  enable_mocks
  create_mock devcontainer 0 ""

  run cmd_workspace_reup
  [ "$status" -eq 0 ]
  assert_mock_called "devcontainer up --workspace-folder ${WORKSPACE_FOLDER} --remove-existing-container"
}

@test "collect_term_env includes remote env flags for set vars" {
  local -a args
  # shellcheck disable=SC2034
  TERM=xterm-kitty
  # shellcheck disable=SC2034
  COLORTERM=truecolor
  collect_term_env args
  [ "${#args[@]}" -eq 4 ]
  [[ "${args[*]}" == *"--remote-env TERM=xterm-kitty"* ]]
  [[ "${args[*]}" == *"--remote-env COLORTERM=truecolor"* ]]
}

@test "cmd_workspace_run forwards terminal env" {
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""

  TERM=xterm-256color COLORTERM=truecolor run cmd_workspace_run -- codex
  [ "$status" -eq 0 ]
  assert_mock_called "--remote-env TERM=xterm-256color"
  assert_mock_called "--remote-env COLORTERM=truecolor"
}

@test "cmd_image_list prints discovered targets from XDG data dir" {
  mkdir -p "${XDG_DATA_HOME}/dctl/images/agents" "${XDG_DATA_HOME}/dctl/images/python-dev"
  touch "${XDG_DATA_HOME}/dctl/images/agents/Dockerfile" "${XDG_DATA_HOME}/dctl/images/python-dev/Dockerfile"

  run cmd_image_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"agents"* ]]
  [[ "$output" == *"python-dev"* ]]
}

@test "cmd_image_build dry-run uses XDG data dir" {
  mkdir -p "${XDG_DATA_HOME}/dctl/images/agents"
  touch "${XDG_DATA_HOME}/dctl/images/agents/Dockerfile"

  run cmd_image_build --dry-run agents
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] Would build: devimg/agents:latest"* ]]
}

@test "cmd_image_build rejects unknown image targets" {
  mkdir -p "${XDG_DATA_HOME}/dctl/images/agents"
  touch "${XDG_DATA_HOME}/dctl/images/agents/Dockerfile"

  run cmd_image_build --dry-run unknown
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown image: unknown"* ]]
}

@test "make install puts Dockerfiles in DATA_DIR/images and installed dctl uses them" {
  local bin_dir data_home lib_dir
  bin_dir="${TEST_TMPDIR}/bin"
  data_home="${TEST_TMPDIR}/data-home"
  lib_dir="${TEST_TMPDIR}/lib/dctl"

  run make install \
    BIN_DIR="$bin_dir" \
    DATA_DIR="${data_home}/dctl" \
    LIB_DIR="$lib_dir"
  [ "$status" -eq 0 ]

  [ -f "${lib_dir}/common.sh" ]
  [ -f "${data_home}/dctl/images/agents/Dockerfile" ]
  [ -f "${data_home}/dctl/templates/python/devcontainer.json" ]

  run env XDG_DATA_HOME="$data_home" HOME="${TEST_TMPDIR}/home" \
    "${bin_dir}/dctl" image list
  [ "$status" -eq 0 ]
  [[ "$output" == *"agents"* ]]
  [[ "$output" == *"python-dev"* ]]
}

@test "discover_templates lists installed templates" {
  create_template_fixture python "devimg/python-dev:latest"
  create_template_fixture rust "devimg/rust-dev:latest"

  run discover_templates
  [ "$status" -eq 0 ]
  [[ "$output" == *"python"* ]]
  [[ "$output" == *"rust"* ]]
}

@test "cmd_init with template creates devcontainer config and runs smoke test" {
  create_template_fixture python "devimg/python-dev:latest"
  # shellcheck disable=SC2329
  cmd_test() { echo "CMD_TEST_CALLED" >>"${TEST_TMPDIR}/mock_calls.log"; }

  run cmd_init --template python
  [ "$status" -eq 0 ]
  [ -f "$(workspace_devcontainer_file)" ]
  grep -F '"image": "devimg/python-dev:latest"' "$(workspace_devcontainer_file)"
  assert_mock_called "CMD_TEST_CALLED"
}

@test "cmd_init warns and preserves existing config without force" {
  create_template_fixture python "devimg/python-dev:latest"
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{\n  "image": "existing-image"\n}\n' >"$(workspace_devcontainer_file)"
  # shellcheck disable=SC2329
  cmd_test() { echo "CMD_TEST_CALLED" >>"${TEST_TMPDIR}/mock_calls.log"; }

  run cmd_init
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping scaffold"* ]]
  grep -F '"image": "existing-image"' "$(workspace_devcontainer_file)"
  assert_mock_called "CMD_TEST_CALLED"
}

@test "cmd_init force overwrites existing config" {
  create_template_fixture python "devimg/python-dev:latest"
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{\n  "image": "existing-image"\n}\n' >"$(workspace_devcontainer_file)"
  # shellcheck disable=SC2329
  cmd_test() { echo "CMD_TEST_CALLED" >>"${TEST_TMPDIR}/mock_calls.log"; }

  run cmd_init --force --template python
  [ "$status" -eq 0 ]
  grep -F '"image": "devimg/python-dev:latest"' "$(workspace_devcontainer_file)"
}

@test "cmd_init rejects unknown templates" {
  create_template_fixture python "devimg/python-dev:latest"
  # shellcheck disable=SC2329
  cmd_test() { echo "CMD_TEST_CALLED" >>"${TEST_TMPDIR}/mock_calls.log"; }

  run cmd_init --template missing
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown template: missing"* ]]
  [[ "$output" == *"python"* ]]
}

@test "cmd_init without template fails non-interactively with available templates" {
  create_template_fixture python "devimg/python-dev:latest"
  enable_mocks
  create_mock fzf 0 "python"
  # shellcheck disable=SC2329
  cmd_test() { echo "CMD_TEST_CALLED" >>"${TEST_TMPDIR}/mock_calls.log"; }

  run cmd_init
  [ "$status" -ne 0 ]
  [[ "$output" == *"Pass --template"* ]]
  [[ "$output" == *"python"* ]]
}

@test "cmd_test fails with init guidance when config is missing" {
  run cmd_test
  [ "$status" -ne 0 ]
  [[ "$output" == *"Run dctl init first"* ]]
}

@test "cmd_test fails when devcontainer command is missing" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{\n  "image": "devimg/python-dev:latest"\n}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock docker 0 "container123"
  PATH="${TEST_TMPDIR}/bin" run cmd_test
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required command: devcontainer"* ]]
}

@test "cmd_test builds managed images before starting the devcontainer" {
  create_image_fixture python-dev
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{\n  "image": "devimg/python-dev:latest"\n}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock docker 0 "container123"
  create_mock devcontainer 0 ""

  run cmd_test
  [ "$status" -eq 0 ]
  assert_mock_called "docker buildx build"
  assert_mock_called "devcontainer up --workspace-folder ${WORKSPACE_FOLDER}"
  assert_mock_called "devcontainer exec --workspace-folder ${WORKSPACE_FOLDER} printf dctl-smoke\n"
  assert_mock_called "docker rm -f"
}

@test "cmd_test skips managed image build for external images" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{\n  "image": "ghcr.io/acme/project:latest"\n}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock docker 0 "container123"
  create_mock devcontainer 0 ""

  run cmd_test
  [ "$status" -eq 0 ]
  assert_mock_not_called "docker buildx build"
  assert_mock_called "devcontainer up --workspace-folder ${WORKSPACE_FOLDER}"
}

@test "root help includes init and test commands" {
  run env XDG_DATA_HOME="$XDG_DATA_HOME" HOME="${TEST_TMPDIR}/home" \
    bash "${BATS_TEST_DIRNAME}/../bin/dctl" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"init"* ]]
  [[ "$output" == *"test"* ]]
}

@test "install-systemd writes a service with the selected BIN_DIR" {
  local systemd_dir bin_dir
  systemd_dir="${TEST_TMPDIR}/systemd-user"
  bin_dir="${TEST_TMPDIR}/bin"

  run make install-systemd BIN_DIR="$bin_dir" SYSTEMD_DIR="$systemd_dir"
  [ "$status" -eq 0 ]

  run grep -F "ExecStart=${bin_dir}/dctl image build --all" \
    "${systemd_dir}/dctl-image-build.service"
  [ "$status" -eq 0 ]
}
