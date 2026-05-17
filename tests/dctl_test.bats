#!/usr/bin/env bats

# bats file_tags=unit

bats_require_minimum_version 1.5.0

load test_helper

source_dctl_functions() {
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
  __dctl_require _lib/workspace/git_worktree.sh
  __dctl_require _lib/workspace/resolve_config.sh
  __dctl_require _lib/workspace/canonical_name.sh
  __dctl_require _lib/workspace/sibling.sh
  __dctl_require _lib/workspace/label_filter.sh
  __dctl_require _lib/workspace/session_hash.sh
  __dctl_require _lib/term/collect_env.sh
  __dctl_require _lib/fzf.sh
  __dctl_require _lib/json/strip_comments.sh
  __dctl_require _lib/json/validate_layer.sh
  __dctl_require _lib/json/merge_runargs.sh
  __dctl_require _lib/json/merge_configs.sh
  __dctl_require _lib/registry/file.sh
  __dctl_require _lib/registry/exists.sh
  __dctl_require _lib/registry/validate_manifest.sh
  __dctl_require _lib/registry/validate.sh
  __dctl_require _lib/registry/read_manifest_layers.sh
  __dctl_require _lib/registry/read_field.sh
  __dctl_require _lib/registry/lookup_manifest.sh
  __dctl_require _lib/registry/lookup_discovery.sh
  __dctl_require _lib/registry/ensure_file.sh
  __dctl_require _lib/registry/has_project.sh
  __dctl_require _lib/registry/register_project_defaults.sh
  __dctl_require commands/ws/_helpers.sh
  __dctl_require commands/ws/_dispatch.sh
  __dctl_require commands/ws/up.sh
  __dctl_require commands/ws/reup.sh
  __dctl_require commands/ws/exec.sh
  __dctl_require commands/ws/shell.sh
  __dctl_require commands/ws/run.sh
  __dctl_require commands/ws/status.sh
  __dctl_require commands/ws/down.sh
  __dctl_require commands/image/_helpers.sh
  __dctl_require commands/image/_dispatch.sh
  __dctl_require commands/image/build.sh
  __dctl_require commands/image/list.sh
  __dctl_require commands/deploy/_dispatch.sh
  __dctl_require commands/init/_dispatch.sh
  __dctl_require commands/init/do.sh
  __dctl_require commands/init/_select_interactive.sh
  __dctl_require commands/init/_generate_cache.sh
  __dctl_require commands/test/_dispatch.sh
  __dctl_require commands/test/run.sh
  __dctl_require commands/config/_dispatch.sh
  __dctl_require commands/net/_dispatch.sh
  __dctl_require commands/net/allow.sh
  __dctl_require commands/net/show.sh
}

create_template_fixture() {
  local name="$1"
  local image="$2"
  mkdir -p "${XDG_DATA_HOME}/dctl/devcontainers/${name}"
  printf '{\n  "image": "%s"\n}\n' "$image" >"${XDG_DATA_HOME}/dctl/devcontainers/${name}/devcontainer.json"
  if [[ $name != "base" ]]; then
    create_installed_manifest_fixture "$name" base "$name"
  fi
}

create_user_devcontainer_fixture() {
  local name="$1"
  local image="$2"
  mkdir -p "${XDG_CONFIG_HOME}/dctl/devcontainer/${name}"
  printf '{\n  "image": "%s"\n}\n' "$image" >"${XDG_CONFIG_HOME}/dctl/devcontainer/${name}/devcontainer.json"
  if [[ $name != "base" ]]; then
    create_user_manifest_fixture "$name" base "$name"
  fi
}

create_installed_manifest_fixture() {
  local name="$1"
  shift
  mkdir -p "${XDG_DATA_HOME}/dctl/devcontainers"
  {
    printf 'layers:\n'
    local layer
    for layer in "$@"; do
      printf '  - %s\n' "$layer"
    done
  } >"${XDG_DATA_HOME}/dctl/devcontainers/${name}.yaml"
}

create_user_manifest_fixture() {
  local name="$1"
  shift
  mkdir -p "${XDG_CONFIG_HOME}/dctl/devcontainer"
  {
    printf 'layers:\n'
    local layer
    for layer in "$@"; do
      printf '  - %s\n' "$layer"
    done
  } >"${XDG_CONFIG_HOME}/dctl/devcontainer/${name}.yaml"
}

create_user_base_layer_fixture() {
  mkdir -p "${XDG_CONFIG_HOME}/dctl/devcontainer/base"
  cat >"${XDG_CONFIG_HOME}/dctl/devcontainer/base/devcontainer.json" <<'USERBASE'
{
  "remoteUser": "testuser",
  "init": true,
  "shutdownAction": "none"
}
USERBASE
}

create_base_template_fixture() {
  mkdir -p "${XDG_DATA_HOME}/dctl/devcontainers/base"
  cat >"${XDG_DATA_HOME}/dctl/devcontainers/base/devcontainer.json" <<'BASEJSON'
{
  "remoteUser": "testuser",
  "init": true,
  "shutdownAction": "none"
}
BASEJSON
}

create_image_fixture() {
  local name="$1"
  mkdir -p "${XDG_DATA_HOME}/dctl/images/${name}"
  touch "${XDG_DATA_HOME}/dctl/images/${name}/Containerfile"
}

create_user_image_fixture() {
  local name="$1"
  mkdir -p "${XDG_CONFIG_HOME}/dctl/images/${name}"
  touch "${XDG_CONFIG_HOME}/dctl/images/${name}/Containerfile"
}

setup() {
  setup_test_fixtures
  export XDG_DATA_HOME="${TEST_TMPDIR}/xdg-data"
  export XDG_CONFIG_HOME="${TEST_TMPDIR}/xdg-config"
  export XDG_CACHE_HOME="${TEST_TMPDIR}/xdg-cache"
  export WORKSPACE_FOLDER="${TEST_TMPDIR}/workspace"
  mkdir -p "${XDG_DATA_HOME}/dctl/images" "${XDG_CONFIG_HOME}/dctl" "${XDG_CACHE_HOME}/dctl" "$WORKSPACE_FOLDER"
  unset DCTL_CONFIG DCTL_CLI_CONFIG 2>/dev/null || true
  source_dctl_functions
  create_base_template_fixture
  create_image_fixture agents
  create_image_fixture python-dev
  create_image_fixture rust-dev
  create_image_fixture zig-dev
  # shellcheck disable=SC2329
  _dctl_krun_preflight() { :; }
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

@test "workspace_label_filter formats podman filter correctly" {
  run workspace_label_filter
  [ "$status" -eq 0 ]
  [ "$output" = "label=devcontainer.local_folder=${WORKSPACE_FOLDER}" ]
}

@test "list_ws_containers uses podman ps -a" {
  enable_mocks
  create_mock podman 0 "abc123"

  run list_ws_containers
  [ "$status" -eq 0 ]
  [ "$output" = "abc123" ]
  assert_mock_called "podman ps --filter"
  assert_mock_called " -a -q"
}

@test "list_running_ws_containers uses podman ps without -a" {
  enable_mocks
  create_mock podman 0 "def456"

  run list_running_ws_containers
  [ "$status" -eq 0 ]
  [ "$output" = "def456" ]
  assert_mock_called "podman ps --filter"
  assert_mock_not_called " -a -q"
}

@test "ensure_ws_container_running skips startup when container is running" {
  enable_mocks
  create_mock podman 0 "running123"

  cmd_ws_up() { echo "CMD_WS_UP_CALLED" >>"${TEST_TMPDIR}/mock_calls.log"; }

  run ensure_ws_container_running
  [ "$status" -eq 0 ]
  assert_mock_not_called "CMD_WS_UP_CALLED"
}

@test "ensure_ws_container_running starts container when needed" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  cat >"${TEST_TMPDIR}/bin/podman" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$(basename "\$0") \$*" >>"${TEST_TMPDIR}/mock_calls.log"
if [[ "\$1" == "ps" ]]; then
  exit 0
fi
printf '%s\n' "container123"
exit 0
EOF
  chmod +x "${TEST_TMPDIR}/bin/podman"

  run ensure_ws_container_running
  [ "$status" -eq 0 ]
  assert_mock_called "podman run --runtime krun --detach"
}

@test "cmd_ws_exec defaults to bash" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock podman 0 "running"

  run cmd_ws_exec
  [ "$status" -eq 0 ]
  assert_mock_called "podman exec"
  assert_mock_called "bash"
}

@test "cmd_ws_exec passes args through" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock podman 0 "running"

  run cmd_ws_exec -- id
  [ "$status" -eq 0 ]
  assert_mock_called "podman exec"
  assert_mock_called "id"
}

@test "cmd_ws_shell runs commands in a login shell" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock podman 0 "running"

  run cmd_ws_shell codex
  [ "$status" -eq 0 ]
  assert_mock_called "podman exec"
  assert_mock_called "bash -lic codex"
}

@test "cmd_ws_run requires a command" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock podman 0 "running"

  run cmd_ws_run
  [ "$status" -ne 0 ]
  [[ $output == *"run requires a command"* ]]
}

@test "cmd_ws_run wraps commands with bash -lc" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock podman 0 "running"

  run cmd_ws_run -- pytest -q
  [ "$status" -eq 0 ]
  assert_mock_called "podman exec"
  assert_mock_called "bash -lc pytest -q"
}

@test "cmd_ws_status does not auto-start a container" {
  enable_mocks
  create_mock podman 0 "abc123"

  run cmd_ws_status
  [ "$status" -eq 0 ]
  assert_mock_not_called "CMD_WS_UP_CALLED"
}

@test "cmd_ws_down warns when nothing matches" {
  enable_mocks
  create_mock podman 0 ""

  run cmd_ws_down
  [ "$status" -eq 0 ]
  [[ $output == *"No devcontainer to remove"* ]]
}

@test "cmd_ws_up passes args to rt_run" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock podman 0 "container123"

  run cmd_ws_up -- --env FOO=bar
  [ "$status" -eq 0 ]
  assert_mock_called "podman run --runtime krun --detach"
  assert_mock_called "--env FOO=bar"
}

@test "cmd_ws_reup removes then reruns the workspace container" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock podman 0 "container123"

  run cmd_ws_reup
  [ "$status" -eq 0 ]
  assert_mock_called "podman rm -f"
  assert_mock_called "podman run --runtime krun --detach"
}

@test "cmd_ws_reup regenerates cached config when a layer mtime is newer" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"

  run generate_cached_devcontainer python
  [ "$status" -eq 0 ]
  local cached="${XDG_CACHE_HOME}/dctl/devcontainer/python/devcontainer.json"
  [ -f "$cached" ]

  sleep 1
  touch "${XDG_CONFIG_HOME}/dctl/devcontainer/python/devcontainer.json"

  enable_mocks
  create_mock podman 0 "container123"

  DCTL_CLI_CONFIG="$cached" run cmd_ws_reup
  [ "$status" -eq 0 ]
  [[ $output == *"Config cache status: generated"* ]]
  assert_mock_called "podman rm -f"
  assert_mock_called "podman run --runtime krun --detach"
}

@test "cmd_ws_reup regenerates manifest-backed cache via registry" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"
  create_user_image_fixture python-dev
  git -C "$WORKSPACE_FOLDER" init -q
  git -C "$WORKSPACE_FOLDER" remote add origin "https://github.com/org/myproj.git"
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<'YAML'
org-myproj:
  devcontainer-manifest: python
YAML

  run generate_cached_devcontainer python
  [ "$status" -eq 0 ]
  local cached="${XDG_CACHE_HOME}/dctl/devcontainer/python/devcontainer.json"

  sleep 1
  touch "${XDG_CONFIG_HOME}/dctl/devcontainer/python/devcontainer.json"

  enable_mocks
  create_mock podman 0 "container123"

  run cmd_ws_reup
  [ "$status" -eq 0 ]
  [[ $output == *"Config cache status: generated"* ]]
  assert_mock_called "podman rm -f"
  assert_mock_called "podman run --runtime krun --detach"
}

@test "cmd_ws_reup reuses cached config when all inputs are older" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"

  run generate_cached_devcontainer python
  [ "$status" -eq 0 ]
  local cached="${XDG_CACHE_HOME}/dctl/devcontainer/python/devcontainer.json"
  [ -f "$cached" ]

  enable_mocks
  create_mock podman 0 "container123"

  DCTL_CLI_CONFIG="$cached" run cmd_ws_reup
  [ "$status" -eq 0 ]
  [[ $output == *"Config cache status: cached"* ]]
  assert_mock_called "podman rm -f"
  assert_mock_called "podman run --runtime krun --detach"
}

@test "cmd_ws_reup does not regenerate when resolved config is outside cache dir" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock podman 0 "container123"

  run cmd_ws_reup
  [ "$status" -eq 0 ]
  [[ $output != *"Config cache status:"* ]]
  assert_mock_called "podman rm -f"
  assert_mock_called "podman run --runtime krun --detach"
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
  [[ ${args[*]} == *"--remote-env TERM=xterm-kitty"* ]]
  [[ ${args[*]} == *"--remote-env COLORTERM=truecolor"* ]]
  [[ ${args[*]} == *"--remote-env KITTY_WINDOW_ID=42"* ]]
  [[ ${args[*]} == *"--remote-env KITTY_LISTEN_ON=unix:/tmp/kitty-test"* ]]
}

@test "cmd_ws_run forwards terminal env" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock podman 0 "running"

  TERM=xterm-256color COLORTERM=truecolor run cmd_ws_run -- codex
  [ "$status" -eq 0 ]
  assert_mock_called "--env TERM=xterm-256color"
  assert_mock_called "--env COLORTERM=truecolor"
}

@test "cmd_image_list prints podman images output" {
  enable_mocks
  create_mock podman 0 $'REPOSITORY:TAG\tIMAGE ID\tCREATED\n devimg/agents:latest\tabc123\tnow'

  run cmd_image_list
  [ "$status" -eq 0 ]
  [[ $output == *"devimg/agents:latest"* ]]
}

@test "cmd_image_build dry-run uses user config dir" {
  create_user_image_fixture agents

  run cmd_image_build --dry-run agents
  [ "$status" -eq 0 ]
  [[ $output == *"[dry-run] Would build: devimg/agents:latest"* ]]
}

@test "cmd_image_build rejects unknown image targets" {
  create_user_image_fixture agents

  run cmd_image_build --dry-run unknown
  [ "$status" -ne 0 ]
  [[ $output == *"Unknown image: unknown"* ]]
}

@test "cmd_image_build with no args invokes picker over deployed images" {
  create_user_image_fixture python-dev
  enable_mocks
  create_mock fzf 0 "python-dev"

  run script -qec "env PATH='${PATH}' XDG_DATA_HOME='${XDG_DATA_HOME}' XDG_CONFIG_HOME='${XDG_CONFIG_HOME}' XDG_CACHE_HOME='${XDG_CACHE_HOME}' WORKSPACE_FOLDER='${WORKSPACE_FOLDER}' DCTL_LIB_DIR='${DCTL_LIB_DIR}' bash -lc 'set -euo pipefail; source \"${DCTL_LIB_DIR}/_lib/source.sh\"; __dctl_require _lib/log.sh; __dctl_require _lib/paths.sh; __dctl_require _lib/fzf.sh; __dctl_require _lib/auth/gh_token.sh; __dctl_require _lib/auth/collect_env.sh; __dctl_require commands/image/build.sh; cmd_image_build --dry-run'" /dev/null
  [ "$status" -eq 0 ]
  [[ $output == *"[dry-run] Would build: devimg/python-dev:latest"* ]]
}

@test "cmd_image_build with no args errors when fzf missing" {
  create_user_image_fixture agents
  # shellcheck disable=SC2329
  command() {
    if [[ $1 == "-v" && $2 == "fzf" ]]; then return 1; fi
    builtin command "$@"
  }

  run cmd_image_build --dry-run
  [ "$status" -ne 0 ]
  [[ $output == *"fzf not found"* ]]

  unset -f command
}

@test "cmd_image_build with no args errors when stdin is not a TTY" {
  create_user_image_fixture agents
  # shellcheck disable=SC2329
  command() {
    if [[ $1 == "-v" && $2 == "fzf" ]]; then return 0; fi
    builtin command "$@"
  }

  run cmd_image_build --dry-run
  [ "$status" -ne 0 ]
  [[ $output == *"requires a terminal"* ]]

  unset -f command
}

@test "cmd_image_build with explicit name builds managed image" {
  create_user_image_fixture agents

  run cmd_image_build --dry-run agents
  [ "$status" -eq 0 ]
  [[ $output == *"devimg/agents:latest"* ]]
}

# bats test_tags=integration
@test "make install puts Containerfiles in DATA_DIR/images" {
  local bin_dir data_home lib_dir
  bin_dir="${TEST_TMPDIR}/bin"
  data_home="${TEST_TMPDIR}/data-home"
  lib_dir="${TEST_TMPDIR}/lib/dctl"

  run make install \
    BIN_DIR="$bin_dir" \
    DATA_DIR="${data_home}/dctl" \
    LIB_DIR="$lib_dir"
  [ "$status" -eq 0 ]

  [ -d "${lib_dir}/commands" ]
  [ -f "${lib_dir}/commands/deploy/_dispatch.sh" ]
  [ -f "${data_home}/dctl/images/agents/Containerfile" ]
  [ -f "${data_home}/dctl/images/zig-dev/zig-zls-init" ]
  [ -x "${data_home}/dctl/images/zig-dev/zig-zls-init" ]
  [ -f "${data_home}/dctl/devcontainers/python/devcontainer.json" ]
  [ -f "${data_home}/dctl/devcontainers/base/devcontainer.json" ]
  [ -f "${data_home}/dctl/devcontainers/python.yaml" ]
  [ -f "${data_home}/dctl/schemas/compose.schema.yaml" ]
}

@test "cmd_init errors when no devcontainers are deployed" {
  run cmd_init_do
  [ "$status" -ne 0 ]
  [[ $output == *"No devcontainers deployed"* ]]
  [[ $output == *"dctl deploy"* ]]
}

@test "cmd_init --help only documents slim flags" {
  run cmd_init_do --help
  [ "$status" -eq 0 ]
  [[ $output == *"--devcontainer"* ]]
  [[ $output == *"--force"* ]]
  [[ $output != *"--image"* ]]
  [[ $output != *"--deploy-only"* ]]
  [[ $output != *"--pick-only"* ]]
  [[ $output != *"--reset"* ]]
}

@test "cmd_init rejects unknown deployed devcontainers" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"

  run cmd_init_do --devcontainer missing
  [ "$status" -ne 0 ]
  [[ $output == *"Unknown deployed devcontainer: missing"* ]]
}

@test "cmd_test fails with init guidance when config is missing" {
  run cmd_test_run
  [ "$status" -ne 0 ]
  [[ $output == *"Run 'dctl init' or pass --config"* ]]
}

@test "cmd_test surfaces krun preflight failures from rt_run" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{\n  "image": "devimg/python-dev:latest"\n}\n' >"$(workspace_devcontainer_file)"
  # shellcheck disable=SC2329
  _dctl_krun_preflight() {
    err "krun runtime preflight failed. Run 'dctl doctor' for full diagnostics."
  }

  run cmd_test_run
  [ "$status" -ne 0 ]
  [[ $output == *"krun runtime preflight failed"* ]]
}

@test "cmd_test builds managed images before starting the devcontainer" {
  create_user_image_fixture python-dev
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{\n  "image": "devimg/python-dev:latest"\n}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock podman 0 "container123"

  run cmd_test_run
  [ "$status" -eq 0 ]
  assert_mock_called "podman build --tag devimg/python-dev:latest"
  assert_mock_called "podman run --runtime krun --detach"
  assert_mock_called "podman exec"
  assert_mock_called "podman rm -f"
}

@test "cmd_test skips managed image build for external images" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{\n  "image": "ghcr.io/acme/project:latest"\n}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock podman 0 "container123"

  run cmd_test_run
  [ "$status" -eq 0 ]
  assert_mock_not_called "podman build --tag"
  assert_mock_called "podman run --runtime krun --detach"
}

# bats test_tags=integration
@test "root help includes deploy, init, and test commands" {
  run env XDG_DATA_HOME="$XDG_DATA_HOME" HOME="${TEST_TMPDIR}/home" \
    bash "${BATS_TEST_DIRNAME}/../bin/dctl" help
  [ "$status" -eq 0 ]
  [[ $output == *"deploy"* ]]
  [[ $output == *"init"* ]]
  [[ $output == *"test"* ]]
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
  git -C "$main_repo" -c user.email=test@example.com -c user.name=Test commit --allow-empty -m "init"
  # Create the linked worktree at $WORKSPACE_FOLDER (which is already set and readonly)
  rm -rf "$WORKSPACE_FOLDER"
  git -C "$main_repo" worktree add "$WORKSPACE_FOLDER" -b test-branch

  local -a mounts=()
  collect_git_worktree_mounts mounts
  [ "${#mounts[@]}" -eq 2 ]
  [ "${mounts[0]}" = "--mount" ]
  [[ ${mounts[1]} == "type=bind,source=${main_repo}/.git,target=${main_repo}/.git" ]]
}

# bats test_tags=integration
@test "ws up includes git worktree mount for linked worktree" {
  local main_repo="${TEST_TMPDIR}/main-repo"
  mkdir -p "$main_repo"
  git -C "$main_repo" init -q
  git -C "$main_repo" -c user.email=test@example.com -c user.name=Test commit --allow-empty -m "init"
  git -C "$main_repo" worktree add "$WORKSPACE_FOLDER" -b test-branch
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"

  enable_mocks
  create_mock podman 0 "container123"

  run cmd_ws_up
  [ "$status" -eq 0 ]
  assert_mock_called "--mount type=bind,source=${main_repo}/.git,target=${main_repo}/.git"
}

# --- Config resolution chain ---

@test "resolve_devcontainer_config returns local file when present" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"

  run resolve_devcontainer_config
  [ "$status" -eq 0 ]
  [[ $output == *"devcontainer.json" ]]
}

@test "resolve_devcontainer_config CLI flag wins over local file" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "local"}\n' >"$(workspace_devcontainer_file)"
  local cli_config="${TEST_TMPDIR}/cli-config.json"
  printf '{"image": "cli"}\n' >"$cli_config"

  DCTL_CLI_CONFIG="$cli_config" run resolve_devcontainer_config
  [ "$status" -eq 0 ]
  [[ $output == *"cli-config.json" ]]
}

@test "resolve_devcontainer_config env var wins over local file" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "local"}\n' >"$(workspace_devcontainer_file)"
  local env_config="${TEST_TMPDIR}/env-config.json"
  printf '{"image": "env"}\n' >"$env_config"

  DCTL_CONFIG="$env_config" run resolve_devcontainer_config
  [ "$status" -eq 0 ]
  [[ $output == *"env-config.json" ]]
}

@test "resolve_devcontainer_config CLI flag wins over env var" {
  local cli_config="${TEST_TMPDIR}/cli-config.json"
  local env_config="${TEST_TMPDIR}/env-config.json"
  printf '{"image": "cli"}\n' >"$cli_config"
  printf '{"image": "env"}\n' >"$env_config"

  DCTL_CLI_CONFIG="$cli_config" DCTL_CONFIG="$env_config" run resolve_devcontainer_config
  [ "$status" -eq 0 ]
  [[ $output == *"cli-config.json" ]]
}

@test "resolve_devcontainer_config errors on missing CLI flag path" {
  DCTL_CLI_CONFIG="/nonexistent/path.json" run resolve_devcontainer_config
  [ "$status" -ne 0 ]
  [[ $output == *"does not exist"* ]]
}

@test "resolve_devcontainer_config errors on missing env var path" {
  DCTL_CONFIG="/nonexistent/path.json" run resolve_devcontainer_config
  [ "$status" -ne 0 ]
  [[ $output == *"does not exist"* ]]
}

@test "resolve_devcontainer_config errors when no config found" {
  run resolve_devcontainer_config
  [ "$status" -ne 0 ]
  [[ $output == *"No devcontainer config found"* ]]
}

@test "resolve_devcontainer_config user global default fallback" {
  mkdir -p "${XDG_CONFIG_HOME}/dctl/default"
  printf '{"image": "default"}\n' >"${XDG_CONFIG_HOME}/dctl/default/devcontainer.json"

  run resolve_devcontainer_config
  [ "$status" -eq 0 ]
  [[ $output == *"default/devcontainer.json" ]]
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
    bash -c 'DCTL_LIB_DIR="'"$DCTL_LIB_DIR"'"; source "'"$DCTL_LIB_DIR"'/_lib/source.sh"; __dctl_require _lib/log.sh; __dctl_require _lib/paths.sh; __dctl_require _lib/workspace/resolve_config.sh; __dctl_require _lib/workspace/canonical_name.sh; __dctl_require _lib/workspace/sibling.sh; __dctl_require _lib/registry/lookup_manifest.sh; __dctl_require _lib/registry/lookup_discovery.sh; resolve_devcontainer_config'
  [ "$status" -eq 0 ]
  [[ $output == *"repo/.devcontainer/devcontainer.json" ]]
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
    bash -c 'DCTL_LIB_DIR="'"$DCTL_LIB_DIR"'"; source "'"$DCTL_LIB_DIR"'/_lib/source.sh"; __dctl_require _lib/log.sh; __dctl_require _lib/paths.sh; __dctl_require _lib/workspace/resolve_config.sh; __dctl_require _lib/workspace/canonical_name.sh; __dctl_require _lib/workspace/sibling.sh; __dctl_require _lib/registry/lookup_manifest.sh; __dctl_require _lib/registry/lookup_discovery.sh; resolve_devcontainer_config'
  [ "$status" -ne 0 ]
  [[ $output == *"No devcontainer config found"* ]]
}

# --- Deploy / init / Containerfile resolution ---

@test "cmd_deploy --help lists new subcommands and flags" {
  run cmd_deploy --help
  [ "$status" -eq 0 ]
  [[ $output == *"devcontainer <name>"* ]]
  [[ $output == *"image <name>"* ]]
  [[ $output == *"--all"* ]]
  [[ $output == *"--all-devcontainers"* ]]
  [[ $output == *"--all-images"* ]]
  [[ $output == *"--dry-run"* ]]
  [[ $output == *"--reset"* ]]
}

@test "cmd_deploy --list shows manifest-backed devcontainer statuses" {
  create_template_fixture python "devimg/python-dev:latest"
  create_user_devcontainer_fixture python "devimg/python-dev:latest"
  create_user_devcontainer_fixture custom "devimg/custom:latest"
  create_user_image_fixture agents
  create_user_image_fixture custom-img

  run cmd_deploy --list
  [ "$status" -eq 0 ]
  [[ $output == *"Devcontainers:"* ]]
  [[ $output == *"Images:"* ]]
  [[ $output == *"deployed  python"* ]]
  [[ $output == *"user-only  custom"* ]]
  [[ $output == *"deployed  agents"* ]]
  [[ $output == *"user-only  custom-img"* ]]
  [[ $output != *$'\n  installed  base'* ]]
}

@test "cmd_deploy --list-devcontainers only lists devcontainers" {
  create_template_fixture python "devimg/python-dev:latest"

  run cmd_deploy --list-devcontainers
  [ "$status" -eq 0 ]
  [[ $output == *"Devcontainers:"* ]]
  [[ $output != *"Images:"* ]]
}

@test "cmd_deploy --list-images only lists images" {
  run cmd_deploy --list-images
  [ "$status" -eq 0 ]
  [[ $output == *"Images:"* ]]
  [[ $output != *"Devcontainers:"* ]]
}

@test "cmd_deploy devcontainer copies selected manifest and managed base layer" {
  create_template_fixture python "devimg/python-dev:latest"

  run cmd_deploy devcontainer python
  [ "$status" -eq 0 ]
  [ -f "${XDG_CONFIG_HOME}/dctl/devcontainer/base/devcontainer.json" ]
  [ -f "${XDG_CONFIG_HOME}/dctl/devcontainer/python/devcontainer.json" ]
  [ -f "${XDG_CONFIG_HOME}/dctl/devcontainer/python.yaml" ]
}

@test "cmd_deploy image copies recursive supporting files and preserves executable bits" {
  create_image_fixture zig-dev
  printf 'FROM alpine\n' >"${XDG_DATA_HOME}/dctl/images/zig-dev/Containerfile"
  mkdir -p "${XDG_DATA_HOME}/dctl/images/zig-dev/hooks"
  printf '#!/usr/bin/env bash\nexit 0\n' >"${XDG_DATA_HOME}/dctl/images/zig-dev/hooks/bootstrap.sh"
  chmod 755 "${XDG_DATA_HOME}/dctl/images/zig-dev/hooks/bootstrap.sh"

  run cmd_deploy image zig-dev
  [ "$status" -eq 0 ]
  [ -f "${XDG_CONFIG_HOME}/dctl/images/zig-dev/Containerfile" ]
  [ -f "${XDG_CONFIG_HOME}/dctl/images/zig-dev/hooks/bootstrap.sh" ]
  [ -x "${XDG_CONFIG_HOME}/dctl/images/zig-dev/hooks/bootstrap.sh" ]
}

@test "cmd_deploy skips existing leaf layer files by default" {
  create_template_fixture python "devimg/python-dev:latest"
  mkdir -p "${XDG_CONFIG_HOME}/dctl/devcontainer/python"
  printf '{"image":"custom"}\n' >"${XDG_CONFIG_HOME}/dctl/devcontainer/python/devcontainer.json"

  run cmd_deploy devcontainer python
  [ "$status" -eq 0 ]
  [ "$(jq -r '.image' "${XDG_CONFIG_HOME}/dctl/devcontainer/python/devcontainer.json")" = "custom" ]
  [[ $output == *"skipped devcontainer 'python'"* ]]
}

@test "cmd_deploy --reset backs up and overwrites shipped files but preserves user-only siblings" {
  create_image_fixture agents
  printf 'FROM installed\n' >"${XDG_DATA_HOME}/dctl/images/agents/Containerfile"
  mkdir -p "${XDG_CONFIG_HOME}/dctl/images/agents"
  printf 'FROM custom\n' >"${XDG_CONFIG_HOME}/dctl/images/agents/Containerfile"
  printf 'notes\n' >"${XDG_CONFIG_HOME}/dctl/images/agents/notes.txt"

  run cmd_deploy image agents --reset
  [ "$status" -eq 0 ]
  [ "$(cat "${XDG_CONFIG_HOME}/dctl/images/agents/Containerfile")" = "FROM installed" ]
  [ -f "${XDG_CONFIG_HOME}/dctl/images/agents/notes.txt" ]
  [ "$(cat "${XDG_CONFIG_HOME}/dctl/images/agents/notes.txt")" = "notes" ]
  # Backup must live next to the original (same parent dir), not somewhere else.
  local backups
  backups=("${XDG_CONFIG_HOME}/dctl/images/agents/Containerfile.bak."*)
  [ "${#backups[@]}" -eq 1 ]
  [ -f "${backups[0]}" ]
  [ "$(cat "${backups[0]}")" = "FROM custom" ]
  # Backup timestamp suffix must match `date -u '+%Y-%m-%dT%H-%M-%SZ'` exactly.
  local suffix="${backups[0]##*Containerfile.bak.}"
  [[ $suffix =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}Z$ ]]
  # No stray backups in unrelated directories.
  run ! compgen -G "${XDG_CONFIG_HOME}/dctl/images/agents/notes.txt.bak.*"
}

@test "cmd_deploy --reset backs up managed shared layers before overwriting" {
  create_template_fixture python "devimg/python-dev:latest"
  run cmd_deploy devcontainer python
  [ "$status" -eq 0 ]
  printf '{"remoteUser":"drifted"}\n' >"${XDG_CONFIG_HOME}/dctl/devcontainer/base/devcontainer.json"

  run cmd_deploy devcontainer python --reset
  [ "$status" -eq 0 ]
  [ "$(jq -r '.remoteUser' "${XDG_CONFIG_HOME}/dctl/devcontainer/base/devcontainer.json")" = "testuser" ]
  local internal_backups
  internal_backups=("${XDG_CONFIG_HOME}/dctl/devcontainer/base/devcontainer.json.bak."*)
  [ "${#internal_backups[@]}" -eq 1 ]
  [ -f "${internal_backups[0]}" ]
  [ "$(jq -r '.remoteUser' "${internal_backups[0]}")" = "drifted" ]
  local suffix="${internal_backups[0]##*devcontainer.json.bak.}"
  [[ $suffix =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}Z$ ]]
}

@test "cmd_deploy reconciles drifted manifest file without reset" {
  create_template_fixture python "devimg/python-dev:latest"

  run cmd_deploy devcontainer python
  [ "$status" -eq 0 ]
  [ -f "${XDG_CONFIG_HOME}/dctl/devcontainer/python.yaml" ]

  # Drift the deployed manifest
  printf 'layers:\n  - base\n  - python\n  - extra\n' >"${XDG_CONFIG_HOME}/dctl/devcontainer/python.yaml"

  run cmd_deploy devcontainer python
  [ "$status" -eq 0 ]
  # Manifest should be reconciled (overwritten) back to installed version
  local deployed_layers installed_layers
  deployed_layers="$(yq eval '.layers | length' "${XDG_CONFIG_HOME}/dctl/devcontainer/python.yaml")"
  installed_layers="$(yq eval '.layers | length' "${XDG_DATA_HOME}/dctl/devcontainers/python.yaml")"
  [ "$deployed_layers" -eq "$installed_layers" ]
  [[ $output == *"reconciled"* ]]
  # No backup created without --reset
  run bash -lc "compgen -G '${XDG_CONFIG_HOME}/dctl/devcontainer/python.yaml.bak.*' >/dev/null"
  [ "$status" -ne 0 ]
}

@test "cmd_deploy --reset backs up drifted manifest file" {
  create_template_fixture python "devimg/python-dev:latest"

  run cmd_deploy devcontainer python
  [ "$status" -eq 0 ]

  # Drift the deployed manifest
  printf 'layers:\n  - base\n  - python\n  - extra\n' >"${XDG_CONFIG_HOME}/dctl/devcontainer/python.yaml"

  run cmd_deploy devcontainer python --reset
  [ "$status" -eq 0 ]
  # Manifest should be overwritten
  local deployed_layers installed_layers
  deployed_layers="$(yq eval '.layers | length' "${XDG_CONFIG_HOME}/dctl/devcontainer/python.yaml")"
  installed_layers="$(yq eval '.layers | length' "${XDG_DATA_HOME}/dctl/devcontainers/python.yaml")"
  [ "$deployed_layers" -eq "$installed_layers" ]
  # Backup must exist
  local backups
  backups=("${XDG_CONFIG_HOME}/dctl/devcontainer/python.yaml.bak."*)
  [ "${#backups[@]}" -eq 1 ]
  [ -f "${backups[0]}" ]
}

@test "cmd_deploy reconciles managed shared layer drift without reset" {
  create_template_fixture python "devimg/python-dev:latest"

  run cmd_deploy devcontainer python
  [ "$status" -eq 0 ]

  printf '{"remoteUser":"drifted"}\n' >"${XDG_CONFIG_HOME}/dctl/devcontainer/base/devcontainer.json"

  run cmd_deploy devcontainer python
  [ "$status" -eq 0 ]
  [ "$(jq -r '.remoteUser' "${XDG_CONFIG_HOME}/dctl/devcontainer/base/devcontainer.json")" = "testuser" ]
  run bash -lc "compgen -G '${XDG_CONFIG_HOME}/dctl/devcontainer/base/devcontainer.json.bak.*' >/dev/null"
  [ "$status" -ne 0 ]
}

@test "cmd_deploy --dry-run prints actions and changes nothing" {
  create_template_fixture python "devimg/python-dev:latest"

  run cmd_deploy devcontainer python --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"CREATE"* ]]
  # Zero filesystem mutations: no target file, no parent dir, no managed shared-layer deploy,
  # no backups, no temp artifacts anywhere under the user config dir.
  [ ! -e "${XDG_CONFIG_HOME}/dctl/devcontainer/python/devcontainer.json" ]
  [ ! -e "${XDG_CONFIG_HOME}/dctl/devcontainer/python" ]
  [ ! -e "${XDG_CONFIG_HOME}/dctl/devcontainer/base" ]
  [ ! -e "${XDG_CONFIG_HOME}/dctl/devcontainer/python.yaml" ]
  run ! compgen -G "${XDG_CONFIG_HOME}/dctl/devcontainer/**/*.bak.*"
  run ! compgen -G "${XDG_CONFIG_HOME}/dctl/**/*.tmp"
}

@test "cmd_deploy --dry-run on existing deploy creates no backups or temp files" {
  create_template_fixture python "devimg/python-dev:latest"
  run cmd_deploy devcontainer python
  [ "$status" -eq 0 ]
  printf '{"remoteUser":"drifted"}\n' >"${XDG_CONFIG_HOME}/dctl/devcontainer/base/devcontainer.json"

  run cmd_deploy devcontainer python --dry-run
  [ "$status" -eq 0 ]
  # Drifted managed shared-layer file untouched, no backups created.
  [ "$(jq -r '.remoteUser' "${XDG_CONFIG_HOME}/dctl/devcontainer/base/devcontainer.json")" = "drifted" ]
  run ! compgen -G "${XDG_CONFIG_HOME}/dctl/devcontainer/base/*.bak.*"
  run ! compgen -G "${XDG_CONFIG_HOME}/dctl/devcontainer/python/*.bak.*"
}

@test "cmd_deploy rejects --dry-run with --reset" {
  run cmd_deploy image agents --dry-run --reset
  [ "$status" -ne 0 ]
  [[ $output == *"Cannot use --dry-run with --reset"* ]]
}

@test "cmd_deploy --all deploys both categories and managed shared layers" {
  create_template_fixture python "devimg/python-dev:latest"
  printf 'FROM alpine\n' >"${XDG_DATA_HOME}/dctl/images/agents/Containerfile"

  run cmd_deploy --all
  [ "$status" -eq 0 ]
  [ -f "${XDG_CONFIG_HOME}/dctl/devcontainer/base/devcontainer.json" ]
  [ -f "${XDG_CONFIG_HOME}/dctl/devcontainer/python/devcontainer.json" ]
  [ -f "${XDG_CONFIG_HOME}/dctl/devcontainer/python.yaml" ]
  [ -f "${XDG_CONFIG_HOME}/dctl/images/agents/Containerfile" ]
}

@test "cmd_deploy --all-devcontainers deploys selectable manifests and managed shared layers only" {
  create_template_fixture python "devimg/python-dev:latest"
  printf 'FROM alpine\n' >"${XDG_DATA_HOME}/dctl/images/agents/Containerfile"

  run cmd_deploy --all-devcontainers
  [ "$status" -eq 0 ]
  [ -f "${XDG_CONFIG_HOME}/dctl/devcontainer/base/devcontainer.json" ]
  [ -f "${XDG_CONFIG_HOME}/dctl/devcontainer/python/devcontainer.json" ]
  [ -f "${XDG_CONFIG_HOME}/dctl/devcontainer/python.yaml" ]
  [ ! -e "${XDG_CONFIG_HOME}/dctl/images/agents/Containerfile" ]
}

@test "cmd_deploy --all-images deploys images only" {
  printf 'FROM alpine\n' >"${XDG_DATA_HOME}/dctl/images/agents/Containerfile"

  run cmd_deploy --all-images
  [ "$status" -eq 0 ]
  [ -f "${XDG_CONFIG_HOME}/dctl/images/agents/Containerfile" ]
  [ ! -e "${XDG_CONFIG_HOME}/dctl/devcontainer/base/devcontainer.json" ]
}

@test "resolve_containerfile fails when only installed image exists" {
  create_image_fixture agents

  run resolve_containerfile agents
  [ "$status" -ne 0 ]
}

@test "resolve_containerfile returns user config path" {
  create_user_image_fixture agents

  run resolve_containerfile agents
  [ "$status" -eq 0 ]
  [[ $output == *"xdg-config"* ]]
}

@test "resolve_containerfile fails for unknown target" {
  run resolve_containerfile nonexistent
  [ "$status" -ne 0 ]
}

@test "discover_image_targets includes user image targets" {
  create_user_image_fixture custom-img
  create_image_fixture agents

  run discover_image_targets
  [ "$status" -eq 0 ]
  [[ $output == *"custom-img"* ]]
  [[ $output != *"agents"* ]]
}

@test "discover_image_targets ignores installed-only targets" {
  create_image_fixture agents

  run discover_image_targets
  [ "$status" -eq 0 ]
  [[ $output != *"agents"* ]]
}

@test "discover_config_layers returns layers in manifest order" {
  mkdir -p "${XDG_CONFIG_HOME}/dctl/devcontainer/base"
  printf '{"name":"base"}\n' >"${XDG_CONFIG_HOME}/dctl/devcontainer/base/devcontainer.json"
  mkdir -p "${XDG_CONFIG_HOME}/dctl/devcontainer/middle"
  printf '{"name":"middle"}\n' >"${XDG_CONFIG_HOME}/dctl/devcontainer/middle/devcontainer.json"
  mkdir -p "${XDG_CONFIG_HOME}/dctl/devcontainer/top"
  printf '{"name":"top"}\n' >"${XDG_CONFIG_HOME}/dctl/devcontainer/top/devcontainer.json"
  create_user_manifest_fixture stack base middle top

  run discover_config_layers stack
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "${XDG_CONFIG_HOME}/dctl/devcontainer/base/devcontainer.json" ]
  [ "${lines[1]}" = "${XDG_CONFIG_HOME}/dctl/devcontainer/middle/devcontainer.json" ]
  [ "${lines[2]}" = "${XDG_CONFIG_HOME}/dctl/devcontainer/top/devcontainer.json" ]
}

@test "_validate_compose_manifest rejects invalid YAML" {
  local manifest="${XDG_CONFIG_HOME}/dctl/devcontainer/broken.yaml"
  mkdir -p "$(dirname "$manifest")"
  printf 'layers: [\n' >"$manifest"

  run _validate_compose_manifest "$manifest"
  [ "$status" -ne 0 ]
  [[ $output == *"Invalid YAML in manifest"* ]]
}

@test "_validate_compose_manifest rejects missing layers key" {
  local manifest="${XDG_CONFIG_HOME}/dctl/devcontainer/broken.yaml"
  mkdir -p "$(dirname "$manifest")"
  printf 'other: value\n' >"$manifest"

  run _validate_compose_manifest "$manifest"
  [ "$status" -ne 0 ]
  [[ $output == *"'layers' must be an array"* ]]
}

@test "_validate_compose_manifest rejects empty layers array" {
  local manifest="${XDG_CONFIG_HOME}/dctl/devcontainer/broken.yaml"
  mkdir -p "$(dirname "$manifest")"
  cat >"$manifest" <<'YAML'
layers: []
YAML

  run _validate_compose_manifest "$manifest"
  [ "$status" -ne 0 ]
  [[ $output == *"'layers' must not be empty"* ]]
}

@test "discover_config_layers errors when manifest references a missing layer" {
  mkdir -p "${XDG_CONFIG_HOME}/dctl/devcontainer/base"
  printf '{"name":"base"}\n' >"${XDG_CONFIG_HOME}/dctl/devcontainer/base/devcontainer.json"
  create_user_manifest_fixture broken base missing

  run discover_config_layers broken
  [ "$status" -ne 0 ]
  [[ $output == *"Layer 'missing' referenced in manifest 'broken' not found"* ]]
}

@test "cmd_deploy errors when manifest references layer with missing devcontainer.json" {
  # Create manifest referencing a layer whose directory exists but has no devcontainer.json
  create_installed_manifest_fixture broken base empty-layer
  create_base_template_fixture
  mkdir -p "${XDG_DATA_HOME}/dctl/devcontainers/empty-layer"
  # No devcontainer.json in empty-layer

  run cmd_deploy devcontainer broken
  [ "$status" -ne 0 ]
  [[ $output == *"devcontainer.json not found"* ]]
  [[ $output == *"empty-layer"* ]]
}

@test "cmd_deploy errors when manifest references nonexistent layer directory" {
  create_installed_manifest_fixture broken base nonexistent
  create_base_template_fixture

  run cmd_deploy devcontainer broken
  [ "$status" -ne 0 ]
  [[ $output == *"installed directory not found"* ]]
  [[ $output == *"nonexistent"* ]]
}

@test "discover_config_layers errors when manifest is missing" {
  run discover_config_layers missing
  [ "$status" -ne 0 ]
  [[ $output == *"No manifest found for 'missing'"* ]]
}

@test "cache_is_fresh checks all layer files" {
  local cached="${TEST_TMPDIR}/cached.json"
  local layer_a="${TEST_TMPDIR}/layer-a.json"
  local layer_b="${TEST_TMPDIR}/layer-b.json"
  local template="${TEST_TMPDIR}/template.json"

  printf '{}\n' >"$layer_a"
  printf '{}\n' >"$layer_b"
  printf '{}\n' >"$template"
  sleep 1
  printf '{}\n' >"$cached"

  run cache_is_fresh "$cached" "$layer_a" "$layer_b" "$template"
  [ "$status" -eq 0 ]

  sleep 1
  touch "$layer_b"
  run cache_is_fresh "$cached" "$layer_a" "$layer_b" "$template"
  [ "$status" -ne 0 ]
}

@test "cache_is_fresh checks manifest files too" {
  local cached="${TEST_TMPDIR}/cached.json"
  local manifest="${TEST_TMPDIR}/python.yaml"
  local layer="${TEST_TMPDIR}/layer.json"

  cat >"$manifest" <<'YAML'
layers:
  - base
  - python
YAML
  printf '{}\n' >"$layer"
  sleep 1
  printf '{}\n' >"$cached"

  run cache_is_fresh "$cached" "$manifest" "$layer"
  [ "$status" -eq 0 ]

  sleep 1
  touch "$manifest"
  run cache_is_fresh "$cached" "$manifest" "$layer"
  [ "$status" -ne 0 ]
}

@test "generate_cached_devcontainer works with manifest-defined layers" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"

  run generate_cached_devcontainer python
  [ "$status" -eq 0 ]

  local deployed="${XDG_CACHE_HOME}/dctl/devcontainer/python/devcontainer.json"
  [ -f "$deployed" ]
  [ "$(jq -r '.remoteUser' "$deployed")" = "testuser" ]
  [ "$(jq -r '.init' "$deployed")" = "true" ]
  [ "$(jq -r '.shutdownAction' "$deployed")" = "none" ]
  [ "$(jq -r '.image' "$deployed")" = "devimg/python-dev:latest" ]
}

@test "generate_cached_devcontainer merges multiple manifest layers with correct ordering" {
  create_user_base_layer_fixture
  mkdir -p "${XDG_CONFIG_HOME}/dctl/devcontainer/middle"
  cat >"${XDG_CONFIG_HOME}/dctl/devcontainer/middle/devcontainer.json" <<'JSON'
{
  "name": "middle",
  "containerEnv": {
    "LEVEL": "middle"
  },
  "mounts": [
    {
      "source": "middle",
      "target": "/middle",
      "type": "volume"
    }
  ]
}
JSON
  mkdir -p "${XDG_CONFIG_HOME}/dctl/devcontainer/python"
  cat >"${XDG_CONFIG_HOME}/dctl/devcontainer/python/devcontainer.json" <<'JSON'
{
  "name": "top",
  "image": "devimg/python-dev:latest",
  "containerEnv": {
    "LEVEL": "top"
  },
  "mounts": [
    {
      "source": "top",
      "target": "/top",
      "type": "volume"
    }
  ]
}
JSON
  create_user_manifest_fixture python base middle python

  run generate_cached_devcontainer python
  [ "$status" -eq 0 ]

  local deployed="${XDG_CACHE_HOME}/dctl/devcontainer/python/devcontainer.json"
  [ -f "$deployed" ]
  [ "$(jq -r '.name' "$deployed")" = "top" ]
  [ "$(jq -r '.containerEnv.LEVEL' "$deployed")" = "top" ]
  [ "$(jq '.mounts | length' "$deployed")" = "2" ]
  [ "$(jq -r '.mounts[0].target' "$deployed")" = "/middle" ]
  [ "$(jq -r '.mounts[1].target' "$deployed")" = "/top" ]
}

@test "cmd_deploy general deploys agents seccomp asset and merged runArgs reference it" {
  create_base_template_fixture
  mkdir -p "${XDG_DATA_HOME}/dctl/devcontainers/agents"
  cat >"${XDG_DATA_HOME}/dctl/devcontainers/agents/devcontainer.json" <<'JSON'
{
  "runArgs": [
    "--security-opt",
    "seccomp=${localEnv:HOME}/.config/dctl/devcontainer/agents/seccomp-bwrap.json",
    "--security-opt",
    "apparmor=unconfined",
    "--security-opt",
    "systempaths=unconfined"
  ]
}
JSON
  printf '{ "defaultAction": "SCMP_ACT_ALLOW" }\n' >"${XDG_DATA_HOME}/dctl/devcontainers/agents/seccomp-bwrap.json"
  mkdir -p "${XDG_DATA_HOME}/dctl/devcontainers/general"
  cat >"${XDG_DATA_HOME}/dctl/devcontainers/general/devcontainer.json" <<'JSON'
{
  "image": "devimg/agents:latest"
}
JSON
  create_installed_manifest_fixture general base agents general

  run cmd_deploy devcontainer general
  [ "$status" -eq 0 ]
  [ -f "${XDG_CONFIG_HOME}/dctl/devcontainer/agents/devcontainer.json" ]
  [ -f "${XDG_CONFIG_HOME}/dctl/devcontainer/agents/seccomp-bwrap.json" ]

  run generate_cached_devcontainer general
  [ "$status" -eq 0 ]

  local deployed="${XDG_CACHE_HOME}/dctl/devcontainer/general/devcontainer.json"
  [ -f "$deployed" ]
  # shellcheck disable=SC2016 # ${localEnv:HOME} is a devcontainer.json variable; must NOT be shell-expanded
  [ "$(jq -r '.runArgs[1]' "$deployed")" = 'seccomp=${localEnv:HOME}/.config/dctl/devcontainer/agents/seccomp-bwrap.json' ]
}

@test "generate_cached_devcontainer merges runArgs/workspaceMount/workspaceFolder across three layers" {
  create_user_base_layer_fixture

  mkdir -p "${XDG_CONFIG_HOME}/dctl/devcontainer/layer-a"
  cat >"${XDG_CONFIG_HOME}/dctl/devcontainer/layer-a/devcontainer.json" <<'JSON'
{
  "workspaceMount": "type=bind,source=ws-a,target=/workspace-a",
  "workspaceFolder": "/ws-a",
  "runArgs": [
    "--name", "foo",
    "--label", "k=v1",
    "--cap-add", "SYS_PTRACE"
  ]
}
JSON

  mkdir -p "${XDG_CONFIG_HOME}/dctl/devcontainer/layer-b"
  cat >"${XDG_CONFIG_HOME}/dctl/devcontainer/layer-b/devcontainer.json" <<'JSON'
{
  "workspaceMount": "type=bind,source=ws-b,target=/workspace-b",
  "runArgs": [
    "--label", "k=v2",
    "--cap-add", "SYS_PTRACE"
  ]
}
JSON

  mkdir -p "${XDG_CONFIG_HOME}/dctl/devcontainer/testmix"
  cat >"${XDG_CONFIG_HOME}/dctl/devcontainer/testmix/devcontainer.json" <<'JSON'
{
  "workspaceFolder": "/ws-c",
  "runArgs": [
    "--name", "bar",
    "--memory", "4g",
    "--cgroup-parent", "user.slice"
  ]
}
JSON

  create_user_manifest_fixture testmix base layer-a layer-b testmix

  run generate_cached_devcontainer testmix
  [ "$status" -eq 0 ]

  local cached="${XDG_CACHE_HOME}/dctl/devcontainer/testmix/devcontainer.json"
  [ "$(jq -r '.workspaceMount' "$cached")" = "type=bind,source=ws-b,target=/workspace-b" ]
  [ "$(jq -r '.workspaceFolder' "$cached")" = "/ws-c" ]
  # --cgroup-parent must be present exactly once (last-wins on a keyed flag whose
  # bracket-subscript key was previously mangled by shfmt).
  [ "$(jq -c '.runArgs' "$cached")" = '["--name","bar","--label","k=v2","--cap-add","SYS_PTRACE","--memory","4g","--cgroup-parent","user.slice","--runtime","krun"]' ]
}

@test "generate_cached_devcontainer errors on unknown top-level keys" {
  create_user_base_layer_fixture

  mkdir -p "${XDG_CONFIG_HOME}/dctl/devcontainer/testbadkey"
  cat >"${XDG_CONFIG_HOME}/dctl/devcontainer/testbadkey/devcontainer.json" <<'JSON'
{
  "image": "devimg/python-dev:latest",
  "unknown_key": 42
}
JSON

  create_user_manifest_fixture testbadkey base testbadkey

  run generate_cached_devcontainer testbadkey
  [ "$status" -ne 0 ]
  [[ $output == *"Unsupported devcontainer.json key: unknown_key"* ]]
  [[ $output == *"testbadkey"* ]]
}

@test "generate_cached_devcontainer reuses cache when fresh" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"

  run generate_cached_devcontainer python
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "generated" ]

  run generate_cached_devcontainer python
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "cached" ]
}

@test "cmd_init reads only user config and ignores installed templates" {
  create_template_fixture python "devimg/rust-dev:latest"
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"
  create_user_image_fixture python-dev
  enable_mocks
  create_mock podman 0 ""
  # shellcheck disable=SC2329
  cmd_test_run() { :; }

  run cmd_init_do --devcontainer python
  [ "$status" -eq 0 ]
  [ "$(jq -r '.image' "${XDG_CACHE_HOME}/dctl/devcontainer/python/devcontainer.json")" = "devimg/python-dev:latest" ]
}

@test "cmd_init errors when managed image Containerfile is not deployed" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"

  run cmd_init_do --devcontainer python
  [ "$status" -ne 0 ]
  [[ $output == *"Image 'python-dev' is not deployed"* ]]
}

@test "cmd_init calls cmd_image_build when managed image is missing locally" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"
  create_user_image_fixture python-dev
  enable_mocks
  create_mock podman 1 ""
  # shellcheck disable=SC2329
  cmd_image_build() { echo "CMD_IMAGE_BUILD_CALLED $*" >>"${TEST_TMPDIR}/mock_calls.log"; }
  # shellcheck disable=SC2329
  cmd_test_run() { :; }

  run cmd_init_do --devcontainer python
  [ "$status" -eq 0 ]
  assert_mock_called "podman image inspect devimg/python-dev:latest"
  assert_mock_called "CMD_IMAGE_BUILD_CALLED python-dev"
}

@test "cmd_init skips build when managed image already exists locally" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"
  create_user_image_fixture python-dev
  enable_mocks
  create_mock podman 0 ""
  # shellcheck disable=SC2329
  cmd_image_build() { echo "CMD_IMAGE_BUILD_CALLED $*" >>"${TEST_TMPDIR}/mock_calls.log"; }
  # shellcheck disable=SC2329
  cmd_test_run() { :; }

  run cmd_init_do --devcontainer python
  [ "$status" -eq 0 ]
  assert_mock_called "podman image inspect devimg/python-dev:latest"
  assert_mock_not_called "CMD_IMAGE_BUILD_CALLED python-dev"
}

@test "cmd_init registers manifest name and produces cache file" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"
  create_user_image_fixture python-dev
  enable_mocks
  create_mock podman 0 ""
  # shellcheck disable=SC2329
  cmd_test_run() { :; }

  run cmd_init_do --devcontainer python
  [ "$status" -eq 0 ]

  local deployed="${XDG_CACHE_HOME}/dctl/devcontainer/python/devcontainer.json"
  local registry="${XDG_CONFIG_HOME}/dctl/projects.yaml"
  local canonical
  canonical="$(resolve_canonical_project_name)"

  [ -f "$deployed" ]
  [ -f "$registry" ]
  [ "$(yq -r ".\"${canonical}\"[\"devcontainer-manifest\"]" "$registry")" = "python" ]
  [ "$(yq -r ".\"${canonical}\" | keys | join(\",\")" "$registry")" = "devcontainer-manifest" ]
  [ "$(yq -r ".\"${canonical}\" | has(\"sibling_discovery\")" "$registry")" = "false" ]
}

@test "cmd_init --force migrates the registry even when unrelated entries are legacy" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"
  create_user_image_fixture python-dev
  enable_mocks
  create_mock podman 0 ""
  local canonical
  canonical="$(resolve_canonical_project_name)"
  local registry="${XDG_CONFIG_HOME}/dctl/projects.yaml"
  # Active project has a legacy entry; an unrelated project also still has
  # one. The forced write must auto-migrate the unrelated entry's legacy
  # `devcontainer:` path to a `devcontainer-manifest` stem (preserving the
  # user's project-selection intent) instead of silently dropping it.
  cat >"$registry" <<YAML
${canonical}:
  devcontainer: \$HOME/active/legacy/devcontainer.json
other-project:
  devcontainer: \$HOME/other/cache/general/devcontainer.json
  sibling_discovery: false
YAML
  # shellcheck disable=SC2329
  cmd_test_run() { :; }

  run cmd_init_do --force --devcontainer python
  [ "$status" -eq 0 ]
  [ "$(yq -r ".\"${canonical}\"[\"devcontainer-manifest\"]" "$registry")" = "python" ]
  [ "$(yq -r ".\"${canonical}\" | has(\"devcontainer\")" "$registry")" = "false" ]
  # Unrelated project's manifest stem is preserved by deriving from
  # basename(dirname(legacy path)), not silently unregistered.
  [ "$(yq -r '.["other-project"]["devcontainer-manifest"]' "$registry")" = "general" ]
  [ "$(yq -r '.["other-project"] | has("devcontainer")' "$registry")" = "false" ]
  [ "$(yq -r '.["other-project"].sibling_discovery' "$registry")" = "false" ]
}

@test "cmd_init --force scrubs legacy devcontainer key for the active project" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"
  create_user_image_fixture python-dev
  enable_mocks
  create_mock podman 0 ""
  local canonical
  canonical="$(resolve_canonical_project_name)"
  local registry="${XDG_CONFIG_HOME}/dctl/projects.yaml"
  # Seed a registry that still uses the legacy `devcontainer:` key for the
  # current project. Without --force this would (correctly) fail strict
  # validation; with --force the lookup must be skipped so register_project_defaults
  # can scrub the legacy key.
  cat >"$registry" <<YAML
${canonical}:
  devcontainer: \$HOME/cache/path/devcontainer.json
  sibling_discovery: false
YAML
  # shellcheck disable=SC2329
  cmd_test_run() { :; }

  run cmd_init_do --force --devcontainer python
  [ "$status" -eq 0 ]
  [ "$(yq -r ".\"${canonical}\"[\"devcontainer-manifest\"]" "$registry")" = "python" ]
  [ "$(yq -r ".\"${canonical}\" | has(\"devcontainer\")" "$registry")" = "false" ]
  [ "$(yq -r ".\"${canonical}\".sibling_discovery" "$registry")" = "false" ]
}

@test "cmd_init --force preserves explicit sibling_discovery: false" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"
  create_user_image_fixture python-dev
  enable_mocks
  create_mock podman 0 ""
  local canonical
  canonical="$(resolve_canonical_project_name)"
  local registry="${XDG_CONFIG_HOME}/dctl/projects.yaml"
  cat >"$registry" <<YAML
${canonical}:
  devcontainer-manifest: rust
  sibling_discovery: false
YAML
  # shellcheck disable=SC2329
  cmd_test_run() { :; }

  run cmd_init_do --force --devcontainer python
  [ "$status" -eq 0 ]
  [ "$(yq -r ".\"${canonical}\"[\"devcontainer-manifest\"]" "$registry")" = "python" ]
  [ "$(yq -r ".\"${canonical}\" | keys | join(\",\")" "$registry")" = "devcontainer-manifest,sibling_discovery" ]
  [ "$(yq -r ".\"${canonical}\".sibling_discovery" "$registry")" = "false" ]
}

@test "cmd_init switches registered manifest when a different deployed devcontainer is selected" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"
  create_user_devcontainer_fixture rust "devimg/rust-dev:latest"
  create_user_image_fixture python-dev
  create_user_image_fixture rust-dev
  enable_mocks
  create_mock podman 0 ""
  # shellcheck disable=SC2329
  cmd_test_run() { :; }

  run cmd_init_do --devcontainer python
  [ "$status" -eq 0 ]

  local canonical
  canonical="$(resolve_canonical_project_name)"
  local registry="${XDG_CONFIG_HOME}/dctl/projects.yaml"

  run cmd_init_do --devcontainer rust
  [ "$status" -eq 0 ]
  [[ $output == *"Switching project"* ]]
  [ "$(yq -r ".\"${canonical}\"[\"devcontainer-manifest\"]" "$registry")" = "rust" ]
}

@test "cmd_init invokes cmd_test and reports the result in the summary" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"
  create_user_image_fixture python-dev
  enable_mocks
  create_mock podman 0 ""
  # shellcheck disable=SC2329
  cmd_test_run() { echo "CMD_TEST_CALLED" >>"${TEST_TMPDIR}/mock_calls.log"; }

  run cmd_init_do --devcontainer python
  [ "$status" -eq 0 ]
  assert_mock_called "CMD_TEST_CALLED"
  [[ $output == *"=== dctl init summary ==="* ]]
  [[ $output == *"Smoke test: passed"* ]]
}

@test "cmd_init reports failed smoke test and exits non-zero" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"
  create_user_image_fixture python-dev
  enable_mocks
  create_mock podman 0 ""
  # shellcheck disable=SC2329
  cmd_test_run() { return 1; }

  run cmd_init_do --devcontainer python
  [ "$status" -ne 0 ]
  [[ $output == *"Smoke test: failed"* ]]
}

@test "cmd_init accepts external images without trying to build" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "ghcr.io/acme/project:latest"
  # shellcheck disable=SC2329
  cmd_image_build() { echo "CMD_IMAGE_BUILD_CALLED $*" >>"${TEST_TMPDIR}/mock_calls.log"; }
  # shellcheck disable=SC2329
  cmd_test_run() { :; }

  run cmd_init_do --devcontainer python
  [ "$status" -eq 0 ]
  [[ $output == *"Image status: external"* ]]
  assert_mock_not_called "CMD_IMAGE_BUILD_CALLED"
}

# --- Bind mount source preflight ---

@test "_resolve_local_env substitutes localEnv vars and leaves literals alone" {
  # shellcheck disable=SC2030
  export HOME=/tmp/fixture-home
  # shellcheck disable=SC2030
  export USER=fixtureuser
  # shellcheck disable=SC2016
  [ "$(_resolve_local_env '${localEnv:HOME}/.config/x')" = "/tmp/fixture-home/.config/x" ]
  # shellcheck disable=SC2016
  [ "$(_resolve_local_env 'prefix-${localEnv:USER}-${localEnv:USER}')" = "prefix-fixtureuser-fixtureuser" ]
  [ "$(_resolve_local_env '/plain/path')" = "/plain/path" ]
}

@test "check_bind_mount_sources passes when all bind sources exist" {
  local cfg="${TEST_TMPDIR}/devcontainer.json"
  local existing="${TEST_TMPDIR}/exists"
  mkdir -p "$existing"
  cat >"$cfg" <<EOF
{
  "mounts": [
    {"source": "${existing}", "target": "/a", "type": "bind"},
    {"source": "vol-x", "target": "/b", "type": "volume"}
  ]
}
EOF
  _check_names=()
  _check_results=()
  run check_bind_mount_sources "$cfg"
  [ "$status" -eq 0 ]
  [[ $output == *"Bind mount sources exist on host"* ]]
}

@test "check_bind_mount_sources reports missing paths with mkdir hint" {
  local cfg="${TEST_TMPDIR}/devcontainer.json"
  local missing_dir="${TEST_TMPDIR}/missing-dir"
  local missing_string="${TEST_TMPDIR}/missing-string"
  cat >"$cfg" <<EOF
{
  "mounts": [
    {"source": "${missing_dir}", "target": "/a", "type": "bind"},
    "type=bind,source=${missing_string},target=/b"
  ]
}
EOF
  _check_names=()
  _check_results=()
  run check_bind_mount_sources "$cfg"
  [ "$status" -eq 1 ]
  [[ $output == *"Missing bind mount source(s) on host"* ]]
  [[ $output == *"$missing_dir"* ]]
  [[ $output == *"$missing_string"* ]]
  [[ $output == *"mkdir -p"* ]]
}

@test "check_bind_mount_sources resolves localEnv and tolerates JSONC comments" {
  # shellcheck disable=SC2030,SC2031
  export HOME="${TEST_TMPDIR}/home"
  mkdir -p "${HOME}/present"
  local cfg="${TEST_TMPDIR}/devcontainer.json"
  cat >"$cfg" <<'EOF'
{
  // leading JSONC comment
  "mounts": [
    {"source": "${localEnv:HOME}/present", "target": "/a", "type": "bind"},
    {"source": "${localEnv:HOME}/absent", "target": "/b", "type": "bind"}
  ]
}
EOF
  _check_names=()
  _check_results=()
  run check_bind_mount_sources "$cfg"
  [ "$status" -eq 1 ]
  [[ $output == *"${HOME}/absent"* ]]
  [[ $output != *"${HOME}/present"$'\n'* ]]
}

@test "check_bind_mount_sources recognizes src= alias in string mounts" {
  local cfg="${TEST_TMPDIR}/devcontainer.json"
  local missing_src="${TEST_TMPDIR}/missing-src"
  cat >"$cfg" <<EOF
{
  "mounts": [
    "type=bind,src=${missing_src},target=/a"
  ]
}
EOF
  _check_names=()
  _check_results=()
  run check_bind_mount_sources "$cfg"
  [ "$status" -eq 1 ]
  [[ $output == *"$missing_src"* ]]
}

@test "check_bind_mount_sources flags unresolved localEnv placeholders" {
  unset DCTL_BIND_MISSING_VAR || true
  local cfg="${TEST_TMPDIR}/devcontainer.json"
  cat >"$cfg" <<'EOF'
{
  "mounts": [
    {"source": "${localEnv:DCTL_BIND_MISSING_VAR}", "target": "/a", "type": "bind"}
  ]
}
EOF
  _check_names=()
  _check_results=()
  run check_bind_mount_sources "$cfg"
  [ "$status" -eq 1 ]
  [[ $output == *"(unresolved)"* ]]
  # shellcheck disable=SC2016
  [[ $output == *'${localEnv:DCTL_BIND_MISSING_VAR}'* ]]
}

@test "check_bind_mount_sources fails on malformed JSON instead of silently passing" {
  local cfg="${TEST_TMPDIR}/devcontainer.json"
  printf '{ not valid json\n' >"$cfg"
  _check_names=()
  _check_results=()
  run check_bind_mount_sources "$cfg"
  [ "$status" -eq 1 ]
  [[ $output == *"Failed to parse bind mounts"* ]]
}

@test "cmd_test skips rt_run when a bind mount source is missing" {
  create_user_image_fixture python-dev
  mkdir -p "$(workspace_devcontainer_dir)"
  local missing="${TEST_TMPDIR}/never-created"
  cat >"$(workspace_devcontainer_file)" <<EOF
{
  "image": "devimg/python-dev:latest",
  "mounts": [
    {"source": "${missing}", "target": "/mnt/x", "type": "bind"}
  ]
  }
EOF
  enable_mocks
  create_mock podman 0 "container123"

  run cmd_test_run
  [ "$status" -ne 0 ]
  [[ $output == *"Missing bind mount source(s) on host"* ]]
  [[ $output == *"$missing"* ]]
  assert_mock_not_called "podman run --runtime krun --detach"
}

@test "collect_ephemeral_cred_mounts copies minimal agent credential files into the session dir" {
  HOME="${TEST_TMPDIR}/home"
  export HOME
  mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.gemini"
  printf 'claude-token\n' >"$HOME/.claude/.credentials.json"
  printf 'codex-token\n' >"$HOME/.codex/auth.json"
  printf 'gemini-token\n' >"$HOME/.gemini/key.json"

  local -a mounts=()
  collect_ephemeral_cred_mounts mounts

  local session_dir
  session_dir="$(workspace_session_dir)"
  [ -f "${session_dir}/claude/.credentials.json" ]
  [ -f "${session_dir}/codex/auth.json" ]
  [ -f "${session_dir}/gemini/key.json" ]
  [[ ${mounts[*]} == *"${session_dir}/claude/.credentials.json"* ]]
  [[ ${mounts[*]} == *"${session_dir}/codex/auth.json"* ]]
  [[ ${mounts[*]} == *"${session_dir}/gemini/key.json"* ]]
  [[ ${mounts[*]} == *"target=${HOME}/.claude/.credentials.json,readonly"* ]]
  [[ ${mounts[*]} == *"target=${HOME}/.codex/auth.json,readonly"* ]]
  [[ ${mounts[*]} == *"target=${HOME}/.gemini/key.json,readonly"* ]]
}

@test "generate_cached_devcontainer writes the effective network allowlist into the cache" {
  create_user_base_layer_fixture
  mkdir -p "${XDG_CONFIG_HOME}/dctl/devcontainer/general"
  cat >"${XDG_CONFIG_HOME}/dctl/devcontainer/general/devcontainer.json" <<'EOF'
{
  "image": "devimg/agents:latest",
  "network": {
    "allow": ["foo.example"]
  }
}
EOF
  create_user_manifest_fixture general base general

  run generate_cached_devcontainer general true
  [ "$status" -eq 0 ]
  local cached="${XDG_CACHE_HOME}/dctl/devcontainer/general/devcontainer.json"
  [ "$(jq -r '.network.allow[]' "$cached" | grep -c '^foo.example$')" -eq 1 ]
  [ "$(jq -r '.network.allow[]' "$cached" | grep -c '^api.anthropic.com$')" -eq 1 ]
}
