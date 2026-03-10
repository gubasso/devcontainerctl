#!/usr/bin/env bats

load test_helper

source_dctl_functions() {
  local script
  script="${BATS_TEST_DIRNAME}/../bin/dctl"
  eval "$(sed -n '1,/^# --- Main/p' "$script" | head -n -1)"
}

setup() {
  setup_test_fixtures
  export XDG_CONFIG_HOME="${TEST_TMPDIR}/xdg-config"
  mkdir -p "${XDG_CONFIG_HOME}/dctl"
  source_dctl_functions
  workspace_path() { echo "/test/workspace"; }
  unset TERM COLORTERM TERM_PROGRAM TERM_PROGRAM_VERSION 2>/dev/null || true
}

teardown() {
  teardown_test_fixtures
}

@test "workspace_label_filter formats docker filter correctly" {
  run workspace_label_filter
  [ "$status" -eq 0 ]
  [ "$output" = "label=devcontainer.local_folder=/test/workspace" ]
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
  assert_mock_called "devcontainer exec --workspace-folder . bash"
}

@test "cmd_workspace_exec passes args through" {
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""

  run cmd_workspace_exec -- id
  [ "$status" -eq 0 ]
  assert_mock_called "devcontainer exec --workspace-folder . id"
}

@test "cmd_workspace_shell runs commands in a login shell" {
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""

  run cmd_workspace_shell codex
  [ "$status" -eq 0 ]
  assert_mock_called "devcontainer exec --workspace-folder . bash -lic codex"
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
  assert_mock_called "devcontainer exec --workspace-folder . bash -lc pytest -q"
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
  assert_mock_called "devcontainer up --workspace-folder . --build-no-cache"
}

@test "cmd_workspace_reup adds remove-existing-container" {
  enable_mocks
  create_mock devcontainer 0 ""

  run cmd_workspace_reup
  [ "$status" -eq 0 ]
  assert_mock_called "devcontainer up --workspace-folder . --remove-existing-container"
}

@test "collect_term_env includes remote env flags for set vars" {
  local -a args
  TERM=xterm-kitty
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

@test "cmd_image_list prints discovered targets from XDG config dir" {
  mkdir -p "${XDG_CONFIG_HOME}/dctl/agents" "${XDG_CONFIG_HOME}/dctl/python-dev"
  touch "${XDG_CONFIG_HOME}/dctl/agents/Dockerfile" "${XDG_CONFIG_HOME}/dctl/python-dev/Dockerfile"

  run cmd_image_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"agents"* ]]
  [[ "$output" == *"python-dev"* ]]
}

@test "cmd_image_build dry-run uses XDG config dir" {
  mkdir -p "${XDG_CONFIG_HOME}/dctl/agents"
  touch "${XDG_CONFIG_HOME}/dctl/agents/Dockerfile"

  run cmd_image_build --dry-run agents
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] Would build: devimg/agents:latest"* ]]
}

@test "cmd_image_build rejects unknown image targets" {
  mkdir -p "${XDG_CONFIG_HOME}/dctl/agents"
  touch "${XDG_CONFIG_HOME}/dctl/agents/Dockerfile"

  run cmd_image_build --dry-run unknown
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown image: unknown"* ]]
}

@test "make install puts Dockerfiles in CONFIG_DIR and installed dctl uses them" {
  local bin_dir config_home data_home
  bin_dir="${TEST_TMPDIR}/bin"
  config_home="${TEST_TMPDIR}/config-home"
  data_home="${TEST_TMPDIR}/data-home"

  run make install \
    BIN_DIR="${bin_dir}" \
    CONFIG_DIR="${config_home}/dctl" \
    DATA_DIR="${data_home}/dctl"
  [ "$status" -eq 0 ]

  [ -f "${config_home}/dctl/agents/Dockerfile" ]
  [ -f "${data_home}/dctl/templates/python/devcontainer.json" ]

  run env XDG_CONFIG_HOME="${config_home}" HOME="${TEST_TMPDIR}/home" \
    "${bin_dir}/dctl" image list
  [ "$status" -eq 0 ]
  [[ "$output" == *"agents"* ]]
  [[ "$output" == *"python-dev"* ]]
}

@test "install-systemd writes a service with the selected BIN_DIR" {
  local systemd_dir bin_dir
  systemd_dir="${TEST_TMPDIR}/systemd-user"
  bin_dir="${TEST_TMPDIR}/bin"

  run make install-systemd BIN_DIR="${bin_dir}" SYSTEMD_DIR="${systemd_dir}"
  [ "$status" -eq 0 ]

  run grep -F "ExecStart=${bin_dir}/dctl image build --all" \
    "${systemd_dir}/dctl-image-build.service"
  [ "$status" -eq 0 ]
}
