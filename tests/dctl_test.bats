#!/usr/bin/env bats

# bats file_tags=unit

load test_helper

source_dctl_functions() {
  local repo_root
  repo_root="${BATS_TEST_DIRNAME}/.."
  readonly DCTL_LIB_DIR="${repo_root}/lib/dctl"
  set -euo pipefail
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/common.sh"
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/auth.sh"
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/ws.sh"
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/image.sh"
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/init.sh"
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/test.sh"
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/config.sh"
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
  export XDG_CONFIG_HOME="${TEST_TMPDIR}/xdg-config"
  export WORKSPACE_FOLDER="${TEST_TMPDIR}/workspace"
  mkdir -p "${XDG_DATA_HOME}/dctl/images" "${XDG_CONFIG_HOME}/dctl" "$WORKSPACE_FOLDER"
  unset DCTL_CONFIG DCTL_CLI_CONFIG 2>/dev/null || true
  source_dctl_functions
  # shellcheck disable=SC2329
  workspace_path() { printf '%s\n' "$WORKSPACE_FOLDER"; }
  # shellcheck disable=SC2329
  workspace_devcontainer_dir() { printf '%s/.devcontainer\n' "$WORKSPACE_FOLDER"; }
  # shellcheck disable=SC2329
  workspace_devcontainer_file() { printf '%s/.devcontainer/devcontainer.json\n' "$WORKSPACE_FOLDER"; }
  unset TERM COLORTERM TERM_PROGRAM TERM_PROGRAM_VERSION 2>/dev/null || true
  unset GH_TOKEN GITHUB_TOKEN GITLAB_TOKEN 2>/dev/null || true
  # Stub gh/glab to fail fast — avoids slow network calls in non-auth tests
  create_mock gh 1
  create_mock glab 1
  enable_mocks
  # Clear git env leaked by pre-commit so in-test git repos work correctly
  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES 2>/dev/null || true
}

teardown() {
  teardown_test_fixtures
}

@test "workspace_label_filter formats docker filter correctly" {
  run workspace_label_filter
  [ "$status" -eq 0 ]
  [ "$output" = "label=devcontainer.local_folder=${WORKSPACE_FOLDER}" ]
}

@test "list_ws_containers uses docker ps -a" {
  enable_mocks
  create_mock docker 0 "abc123"

  run list_ws_containers
  [ "$status" -eq 0 ]
  [ "$output" = "abc123" ]
  assert_mock_called "docker ps -a"
}

@test "list_running_ws_containers uses docker ps without -a" {
  enable_mocks
  create_mock docker 0 "def456"

  run list_running_ws_containers
  [ "$status" -eq 0 ]
  [ "$output" = "def456" ]
  assert_mock_called "docker ps --filter"
  assert_mock_not_called "docker ps -a"
}

@test "ensure_ws_container_running skips startup when container is running" {
  enable_mocks
  create_mock docker 0 "running123"
  create_mock devcontainer 0 ""

  cmd_ws_up() { echo "CMD_WS_UP_CALLED" >>"${TEST_TMPDIR}/mock_calls.log"; }

  run ensure_ws_container_running
  [ "$status" -eq 0 ]
  assert_mock_not_called "CMD_WS_UP_CALLED"
}

@test "ensure_ws_container_running starts container when needed" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock docker 0 ""
  create_mock devcontainer 0 ""

  run ensure_ws_container_running
  [ "$status" -eq 0 ]
  assert_mock_called "devcontainer up"
}

@test "cmd_ws_exec defaults to bash" {
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""

  run cmd_ws_exec
  [ "$status" -eq 0 ]
  assert_mock_called "devcontainer exec"
  assert_mock_called "bash"
}

@test "cmd_ws_exec passes args through" {
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""

  run cmd_ws_exec -- id
  [ "$status" -eq 0 ]
  assert_mock_called "devcontainer exec"
  assert_mock_called "id"
}

@test "cmd_ws_shell runs commands in a login shell" {
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""

  run cmd_ws_shell codex
  [ "$status" -eq 0 ]
  assert_mock_called "devcontainer exec"
  assert_mock_called "bash -lic codex"
}

@test "cmd_ws_run requires a command" {
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""

  run cmd_ws_run
  [ "$status" -ne 0 ]
  [[ "$output" == *"run requires a command"* ]]
}

@test "cmd_ws_run wraps commands with bash -lc" {
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""

  run cmd_ws_run -- pytest -q
  [ "$status" -eq 0 ]
  assert_mock_called "devcontainer exec"
  assert_mock_called "bash -lc pytest -q"
}

@test "cmd_ws_status does not auto-start a container" {
  enable_mocks
  create_mock docker 0 "abc123"

  run cmd_ws_status
  [ "$status" -eq 0 ]
  assert_mock_not_called "devcontainer up"
}

@test "cmd_ws_down warns when nothing matches" {
  enable_mocks
  create_mock docker 0 ""

  run cmd_ws_down
  [ "$status" -eq 0 ]
  [[ "$output" == *"No devcontainer to remove"* ]]
}

@test "cmd_ws_up passes args to devcontainer up" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock devcontainer 0 ""

  run cmd_ws_up -- --build-no-cache
  [ "$status" -eq 0 ]
  assert_mock_called "devcontainer up --workspace-folder ${WORKSPACE_FOLDER} --config $(workspace_devcontainer_file) --build-no-cache"
}

@test "cmd_ws_reup adds remove-existing-container" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock devcontainer 0 ""

  run cmd_ws_reup
  [ "$status" -eq 0 ]
  assert_mock_called "devcontainer up --workspace-folder ${WORKSPACE_FOLDER} --config $(workspace_devcontainer_file) --remove-existing-container"
}

@test "collect_term_env includes remote env flags for set vars" {
  local -a args
  # shellcheck disable=SC2034
  TERM=xterm-kitty
  # shellcheck disable=SC2034
  COLORTERM=truecolor
  # shellcheck disable=SC2034
  KITTY_WINDOW_ID=42
  # shellcheck disable=SC2034
  KITTY_LISTEN_ON=unix:/tmp/kitty-test
  collect_term_env args
  [ "${#args[@]}" -eq 8 ]
  [[ "${args[*]}" == *"--remote-env TERM=xterm-kitty"* ]]
  [[ "${args[*]}" == *"--remote-env COLORTERM=truecolor"* ]]
  [[ "${args[*]}" == *"--remote-env KITTY_WINDOW_ID=42"* ]]
  [[ "${args[*]}" == *"--remote-env KITTY_LISTEN_ON=unix:/tmp/kitty-test"* ]]
}

@test "cmd_ws_run forwards terminal env" {
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""

  TERM=xterm-256color COLORTERM=truecolor run cmd_ws_run -- codex
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

# bats test_tags=integration
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

  # Redirect stdin from /dev/null to ensure non-interactive detection
  # works even when bats preserves the host terminal under `run`
  run cmd_init </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"Pass --template"* ]]
  [[ "$output" == *"python"* ]]
}

@test "cmd_test fails with init guidance when config is missing" {
  run cmd_test
  [ "$status" -ne 0 ]
  [[ "$output" == *"Run 'dctl init' or pass --config"* ]]
}

@test "cmd_test fails when devcontainer command is missing" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{\n  "image": "devimg/python-dev:latest"\n}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock docker 0 "container123"
  PATH="${TEST_TMPDIR}/bin:/usr/bin:/bin" run cmd_test
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
  assert_mock_called "devcontainer up --workspace-folder ${WORKSPACE_FOLDER} --config"
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
  assert_mock_called "devcontainer up --workspace-folder ${WORKSPACE_FOLDER} --config"
}

# bats test_tags=integration
@test "root help includes init and test commands" {
  run env XDG_DATA_HOME="$XDG_DATA_HOME" HOME="${TEST_TMPDIR}/home" \
    bash "${BATS_TEST_DIRNAME}/../bin/dctl" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"init"* ]]
  [[ "$output" == *"test"* ]]
}

# bats test_tags=integration
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

# Dotfiles validation

@test "ws up fails early when dotfiles directory is missing" {
  local missing_home
  missing_home="${TEST_TMPDIR}/home-no-dotfiles"
  mkdir -p "$missing_home"

  enable_mocks
  create_mock devcontainer 0 ""

  unset DOTFILES
  HOME="$missing_home" run cmd_ws_up
  [ "$status" -eq 1 ]
  [[ "$output" == *"Dotfiles not found"* ]]
  assert_mock_not_called "devcontainer "
}

@test "ws reup fails early when dotfiles directory is missing" {
  local missing_home
  missing_home="${TEST_TMPDIR}/home-no-dotfiles"
  mkdir -p "$missing_home"

  enable_mocks
  create_mock devcontainer 0 ""

  unset DOTFILES
  HOME="$missing_home" run cmd_ws_reup
  [ "$status" -eq 1 ]
  [[ "$output" == *"Dotfiles not found"* ]]
  assert_mock_not_called "devcontainer "
}

# --- Git worktree mount detection ---

@test "collect_git_worktree_mounts returns empty for non-git workspace" {
  local -a mounts=()
  collect_git_worktree_mounts mounts
  [ "${#mounts[@]}" -eq 0 ]
}

@test "collect_git_worktree_mounts returns empty for regular git repo" {
  git -C "$WORKSPACE_FOLDER" init -q
  local -a mounts=()
  collect_git_worktree_mounts mounts
  [ "${#mounts[@]}" -eq 0 ]
}

# bats test_tags=integration
@test "collect_git_worktree_mounts returns mount for linked worktree" {
  local main_repo="${TEST_TMPDIR}/main-repo"
  mkdir -p "$main_repo"
  git -C "$main_repo" init -q
  git -C "$main_repo" commit --allow-empty -m "init"
  # Create the linked worktree at $WORKSPACE_FOLDER (which is already set and readonly)
  rm -rf "$WORKSPACE_FOLDER"
  git -C "$main_repo" worktree add "$WORKSPACE_FOLDER" -b test-branch

  local -a mounts=()
  collect_git_worktree_mounts mounts
  [ "${#mounts[@]}" -eq 2 ]
  [ "${mounts[0]}" = "--mount" ]
  [[ "${mounts[1]}" == "type=bind,source=${main_repo}/.git,target=${main_repo}/.git" ]]
}

# bats test_tags=integration
@test "ws up includes git worktree mount for linked worktree" {
  local main_repo="${TEST_TMPDIR}/main-repo"
  mkdir -p "$main_repo"
  git -C "$main_repo" init -q
  git -C "$main_repo" commit --allow-empty -m "init"
  git -C "$main_repo" worktree add "$WORKSPACE_FOLDER" -b test-branch
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"

  enable_mocks
  create_mock devcontainer 0 ""

  run cmd_ws_up
  [ "$status" -eq 0 ]
  assert_mock_called "--mount type=bind,source=${main_repo}/.git,target=${main_repo}/.git"
}

@test "ws up calls devcontainer when DOTFILES is valid" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock devcontainer 0 ""

  DOTFILES="${TEST_TMPDIR}/dotfiles"
  mkdir -p "$DOTFILES"

  run cmd_ws_up
  [ "$status" -eq 0 ]
  assert_mock_called "devcontainer up --workspace-folder ${WORKSPACE_FOLDER} --config"
}

# --- Auth token forwarding via devcontainer exec ---

@test "cmd_ws_shell forwards GH_TOKEN via remote-env" {
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""
  cat >"${TEST_TMPDIR}/bin/gh" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == "auth" && "$2" == "status" ]] && exit 0
[[ "$1" == "auth" && "$2" == "token" ]] && printf 'ghp_testXYZ' && exit 0
exit 1
MOCK
  chmod +x "${TEST_TMPDIR}/bin/gh"

  run cmd_ws_shell
  [ "$status" -eq 0 ]
  assert_mock_called "--remote-env GH_TOKEN=ghp_testXYZ"
}

@test "cmd_ws_shell forwards GITLAB_TOKEN via remote-env" {
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""
  cat >"${TEST_TMPDIR}/bin/glab" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == "auth" && "$2" == "status" && "$3" != "--show-token" ]] && exit 0
[[ "$1" == "auth" && "$2" == "status" && "$3" == "--show-token" ]] && printf 'Token: glpat_testABC\n' && exit 0
exit 1
MOCK
  chmod +x "${TEST_TMPDIR}/bin/glab"

  run cmd_ws_shell
  [ "$status" -eq 0 ]
  assert_mock_called "--remote-env GITLAB_TOKEN=glpat_testABC"
}

@test "cmd_ws_shell forwards both tokens when both CLIs authenticated" {
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""
  cat >"${TEST_TMPDIR}/bin/gh" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == "auth" && "$2" == "status" ]] && exit 0
[[ "$1" == "auth" && "$2" == "token" ]] && printf 'ghp_both999' && exit 0
exit 1
MOCK
  chmod +x "${TEST_TMPDIR}/bin/gh"
  cat >"${TEST_TMPDIR}/bin/glab" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == "auth" && "$2" == "status" && "$3" != "--show-token" ]] && exit 0
[[ "$1" == "auth" && "$2" == "status" && "$3" == "--show-token" ]] && printf 'Token: glpat_both888\n' && exit 0
exit 1
MOCK
  chmod +x "${TEST_TMPDIR}/bin/glab"

  run cmd_ws_shell
  [ "$status" -eq 0 ]
  assert_mock_called "--remote-env GH_TOKEN=ghp_both999"
  assert_mock_called "--remote-env GITLAB_TOKEN=glpat_both888"
}

# --- Config resolution chain ---

@test "resolve_devcontainer_config returns local file when present" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"

  run resolve_devcontainer_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"devcontainer.json" ]]
}

@test "resolve_devcontainer_config CLI flag wins over local file" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "local"}\n' >"$(workspace_devcontainer_file)"
  local cli_config="${TEST_TMPDIR}/cli-config.json"
  printf '{"image": "cli"}\n' >"$cli_config"

  DCTL_CLI_CONFIG="$cli_config" run resolve_devcontainer_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"cli-config.json" ]]
}

@test "resolve_devcontainer_config env var wins over local file" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "local"}\n' >"$(workspace_devcontainer_file)"
  local env_config="${TEST_TMPDIR}/env-config.json"
  printf '{"image": "env"}\n' >"$env_config"

  DCTL_CONFIG="$env_config" run resolve_devcontainer_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"env-config.json" ]]
}

@test "resolve_devcontainer_config CLI flag wins over env var" {
  local cli_config="${TEST_TMPDIR}/cli-config.json"
  local env_config="${TEST_TMPDIR}/env-config.json"
  printf '{"image": "cli"}\n' >"$cli_config"
  printf '{"image": "env"}\n' >"$env_config"

  DCTL_CLI_CONFIG="$cli_config" DCTL_CONFIG="$env_config" run resolve_devcontainer_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"cli-config.json" ]]
}

@test "resolve_devcontainer_config errors on missing CLI flag path" {
  DCTL_CLI_CONFIG="/nonexistent/path.json" run resolve_devcontainer_config
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "resolve_devcontainer_config errors on missing env var path" {
  DCTL_CONFIG="/nonexistent/path.json" run resolve_devcontainer_config
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "resolve_devcontainer_config errors when no config found" {
  run resolve_devcontainer_config
  [ "$status" -ne 0 ]
  [[ "$output" == *"No devcontainer config found"* ]]
}

@test "resolve_devcontainer_config user global default fallback" {
  mkdir -p "${XDG_CONFIG_HOME}/dctl/default"
  printf '{"image": "default"}\n' >"${XDG_CONFIG_HOME}/dctl/default/devcontainer.json"

  run resolve_devcontainer_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"default/devcontainer.json" ]]
}

# bats test_tags=integration
@test "resolve_devcontainer_config sibling discovery finds main repo config" {
  local parent="${TEST_TMPDIR}/projects"
  local main_repo="${parent}/repo"
  local work_clone="${parent}/repo.42-feature"
  mkdir -p "$main_repo/.devcontainer" "$work_clone"
  printf '{"image": "sibling"}\n' >"$main_repo/.devcontainer/devcontainer.json"
  git -C "$main_repo" init -q

  run env WORKSPACE_FOLDER="$work_clone" XDG_DATA_HOME="$XDG_DATA_HOME" \
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    bash -c 'source "'"$DCTL_LIB_DIR"'/common.sh"; source "'"$DCTL_LIB_DIR"'/config.sh"; resolve_devcontainer_config'
  [ "$status" -eq 0 ]
  [[ "$output" == *"repo/.devcontainer/devcontainer.json" ]]
}

# bats test_tags=integration
@test "resolve_devcontainer_config sibling skipped for non-git directory" {
  local parent="${TEST_TMPDIR}/projects"
  local main_repo="${parent}/repo"
  local work_clone="${parent}/repo.42-feature"
  mkdir -p "$main_repo/.devcontainer" "$work_clone"
  printf '{"image": "sibling"}\n' >"$main_repo/.devcontainer/devcontainer.json"
  # No git init — should not be discovered

  run env WORKSPACE_FOLDER="$work_clone" XDG_DATA_HOME="$XDG_DATA_HOME" \
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    bash -c 'source "'"$DCTL_LIB_DIR"'/common.sh"; source "'"$DCTL_LIB_DIR"'/config.sh"; resolve_devcontainer_config'
  [ "$status" -ne 0 ]
  [[ "$output" == *"No devcontainer config found"* ]]
}

# --- Template discovery ---

@test "discover_templates includes user templates" {
  create_template_fixture python "devimg/python-dev:latest"
  mkdir -p "${XDG_CONFIG_HOME}/dctl/templates/custom"
  printf '{"image": "custom"}\n' >"${XDG_CONFIG_HOME}/dctl/templates/custom/devcontainer.json"

  run discover_templates
  [ "$status" -eq 0 ]
  [[ "$output" == *"python"* ]]
  [[ "$output" == *"custom"* ]]
}

@test "user template overrides installed template with same name" {
  create_template_fixture python "devimg/python-dev:latest"
  mkdir -p "${XDG_CONFIG_HOME}/dctl/templates/python"
  printf '{"image": "user-python"}\n' >"${XDG_CONFIG_HOME}/dctl/templates/python/devcontainer.json"

  local path
  path="$(template_path python)"
  [[ "$path" == *"xdg-config"* ]]
  grep -q "user-python" "$path"
}

@test "cmd_init --list prints templates to stdout" {
  create_template_fixture python "devimg/python-dev:latest"

  run cmd_init --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"python"* ]]
}

# --- Dockerfile resolution ---

@test "resolve_dockerfile returns installed path" {
  create_image_fixture agents

  run resolve_dockerfile agents
  [ "$status" -eq 0 ]
  [[ "$output" == *"agents/Dockerfile" ]]
}

@test "resolve_dockerfile user override wins over installed" {
  create_image_fixture agents
  mkdir -p "${XDG_CONFIG_HOME}/dctl/images/agents"
  touch "${XDG_CONFIG_HOME}/dctl/images/agents/Dockerfile"

  run resolve_dockerfile agents
  [ "$status" -eq 0 ]
  [[ "$output" == *"xdg-config"* ]]
}

@test "resolve_dockerfile fails for unknown target" {
  run resolve_dockerfile nonexistent
  [ "$status" -ne 0 ]
}

@test "cmd_image_build uses registry managed target when no CLI target" {
  create_image_fixture python-dev
  local canonical
  canonical="$(resolve_canonical_project_name)"
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<YAML
${canonical}:
  dockerfile: python-dev
YAML

  run cmd_image_build --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"devimg/python-dev:latest"* ]]
}

@test "cmd_image_build uses registry direct path when set" {
  local custom_dir="${TEST_TMPDIR}/custom-docker"
  mkdir -p "$custom_dir"
  printf 'FROM alpine\n' >"$custom_dir/Dockerfile"
  local canonical
  canonical="$(resolve_canonical_project_name)"
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<YAML
${canonical}:
  dockerfile: ${custom_dir}/Dockerfile
YAML

  run cmd_image_build --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"direct path"* ]]
}

@test "cmd_image_build CLI target wins over registry dockerfile" {
  create_image_fixture agents
  create_image_fixture python-dev
  local canonical
  canonical="$(resolve_canonical_project_name)"
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<YAML
${canonical}:
  dockerfile: python-dev
YAML

  run cmd_image_build --dry-run agents
  [ "$status" -eq 0 ]
  [[ "$output" == *"devimg/agents:latest"* ]]
  [[ "$output" != *"python-dev"* ]]
}

@test "discover_image_targets includes user image targets" {
  create_image_fixture agents
  mkdir -p "${XDG_CONFIG_HOME}/dctl/images/custom-img"
  touch "${XDG_CONFIG_HOME}/dctl/images/custom-img/Dockerfile"

  run discover_image_targets
  [ "$status" -eq 0 ]
  [[ "$output" == *"agents"* ]]
  [[ "$output" == *"custom-img"* ]]
}
