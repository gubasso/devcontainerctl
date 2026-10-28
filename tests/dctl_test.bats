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

# A seed that an older release installed under XDG_DATA_HOME. dctl ignores it.
create_stale_seed_template_fixture() {
  local name="$1"
  local image="$2"
  mkdir -p "${XDG_DATA_HOME}/dctl/devcontainers/${name}"
  printf '{\n  "image": "%s"\n}\n' "$image" >"${XDG_DATA_HOME}/dctl/devcontainers/${name}/devcontainer.json"
  if [[ $name != "base" ]]; then
    create_stale_seed_manifest_fixture "$name" base "$name"
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

create_stale_seed_manifest_fixture() {
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

create_stale_seed_image_fixture() {
  local name="$1"
  mkdir -p "${XDG_DATA_HOME}/dctl/images/${name}"
  touch "${XDG_DATA_HOME}/dctl/images/${name}/Dockerfile"
}

create_user_image_fixture() {
  local name="$1"
  mkdir -p "${XDG_CONFIG_HOME}/dctl/images/${name}"
  touch "${XDG_CONFIG_HOME}/dctl/images/${name}/Dockerfile"
}

create_user_image_dockerfile() {
  local name="$1"
  shift
  mkdir -p "${XDG_CONFIG_HOME}/dctl/images/${name}"
  printf '%s\n' "$@" >"${XDG_CONFIG_HOME}/dctl/images/${name}/Dockerfile"
}

# base <- agents <- {child-a, child-b}, with one external base per managed image and a
# multi-stage agents Dockerfile.
create_image_family_fixture() {
  create_user_image_dockerfile base 'FROM opensuse/tumbleweed AS base'
  create_user_image_dockerfile agents 'FROM rust:1-slim AS tools' 'FROM devimg/base:latest'
  create_user_image_dockerfile child-a 'FROM devimg/agents:latest'
  create_user_image_dockerfile child-b 'FROM devimg/agents:latest'
}

dry_run_build_order() {
  printf '%s\n' "$1" \
    | sed -n 's#.*Would build: devimg/\([^:]*\):latest.*#\1#p' \
    | tr '\n' ' '
}

setup() {
  setup_test_fixtures
  export XDG_DATA_HOME="${TEST_TMPDIR}/xdg-data"
  export XDG_CONFIG_HOME="${TEST_TMPDIR}/xdg-config"
  export XDG_CACHE_HOME="${TEST_TMPDIR}/xdg-cache"
  # The merged config is regenerated (never cached); it lands under
  # $XDG_RUNTIME_DIR/dctl/devcontainer/<manifest>/devcontainer.json.
  export XDG_RUNTIME_DIR="${TEST_TMPDIR}/xdg-runtime"
  export WORKSPACE_FOLDER="${TEST_TMPDIR}/workspace"
  mkdir -p "${XDG_CONFIG_HOME}/dctl" "${XDG_RUNTIME_DIR}/dctl" "$WORKSPACE_FOLDER"
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
  unset SSH_AUTH_SOCK GH_CONFIG_DIR GLAB_CONFIG_DIR 2>/dev/null || true
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
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""

  run cmd_ws_exec
  [ "$status" -eq 0 ]
  assert_mock_called "devcontainer exec"
  assert_mock_called "bash"
}

@test "cmd_ws_exec passes args through" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""

  run cmd_ws_exec -- id
  [ "$status" -eq 0 ]
  assert_mock_called "devcontainer exec"
  assert_mock_called "id"
}

@test "cmd_ws_shell runs commands in a login shell" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""

  run cmd_ws_shell codex
  [ "$status" -eq 0 ]
  assert_mock_called "devcontainer exec"
  assert_mock_called "bash -lic ''codex"
}

@test "cmd_ws_run requires a command" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""

  run cmd_ws_run
  [ "$status" -ne 0 ]
  [[ $output == *"run requires a command"* ]]
}

@test "cmd_ws_run wraps commands with bash -lc" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""

  run cmd_ws_run -- pytest -q
  [ "$status" -eq 0 ]
  assert_mock_called "devcontainer exec"
  assert_mock_called "bash -lc ''pytest -q"
}

ws_quoting_fixture() {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock docker 0 "running"
  create_devcontainer_shell_mock
}

# The tests run with --separate-stderr, because dctl reports the config it
# uses and the forge seed on stderr, and only the command's stdout is compared.
#
# Each word below is one hard case: a space, an empty word, a single and a
# double quote, a literal ;, |, and $, and a newline.
ws_quoting_expected() {
  # shellcheck disable=SC2016 # the literal $HOME is the case under test
  printf '%s\n' '<a b>' '<>' "<it's>" '<say "hi">' '<x;y>' '<p|q>' '<$HOME>' '<l1' 'l2>'
}

@test "cmd_ws_run keeps each word as one argument" {
  ws_quoting_fixture

  # shellcheck disable=SC2016 # the literal $HOME is the case under test
  run --separate-stderr cmd_ws_run -- printf '<%s>\n' 'a b' '' "it's" 'say "hi"' 'x;y' 'p|q' '$HOME' $'l1\nl2'
  [ "$status" -eq 0 ]
  [ "$output" = "$(ws_quoting_expected)" ]
}

@test "cmd_ws_shell keeps each word as one argument" {
  ws_quoting_fixture

  # shellcheck disable=SC2016 # the literal $HOME is the case under test
  run --separate-stderr cmd_ws_shell printf '<%s>\n' 'a b' '' "it's" 'say "hi"' 'x;y' 'p|q' '$HOME' $'l1\nl2'
  [ "$status" -eq 0 ]
  [ "$output" = "$(ws_quoting_expected)" ]
}

@test "cmd_ws_run passes two words as two arguments" {
  ws_quoting_fixture

  run --separate-stderr cmd_ws_run -- printf '%s\n' 'a b' c
  [ "$status" -eq 0 ]
  [ "$output" = $'a b\nc' ]
}

@test "cmd_ws_run runs a shell expression only through an explicit shell" {
  ws_quoting_fixture

  run --separate-stderr cmd_ws_run -- echo 'one && echo two'
  [ "$status" -eq 0 ]
  [ "$output" = "one && echo two" ]

  run --separate-stderr cmd_ws_run -- bash -c 'echo one && echo two'
  [ "$status" -eq 0 ]
  [ "$output" = $'one\ntwo' ]
}

@test "cmd_ws_shell runs a shell expression only through an explicit shell" {
  ws_quoting_fixture

  run --separate-stderr cmd_ws_shell echo 'one; echo two'
  [ "$status" -eq 0 ]
  [ "$output" = "one; echo two" ]

  run --separate-stderr cmd_ws_shell bash -c 'echo one; echo two'
  [ "$status" -eq 0 ]
  [ "$output" = $'one\ntwo' ]
}

# Commands whose names bash would read as a reserved word or an assignment
# when the first word is left bare. Each fixture prints its name and its
# arguments.
ws_command_name_fixtures() {
  local name
  for name in time for A=B; do
    cat >"${TEST_TMPDIR}/bin/${name}" <<'EOF'
#!/usr/bin/env bash
printf '%s:[%s]\n' "${0##*/}" "$*"
EOF
    chmod +x "${TEST_TMPDIR}/bin/${name}"
  done
}

@test "cmd_ws_run runs a command named like a reserved word or an assignment" {
  ws_quoting_fixture
  ws_command_name_fixtures

  local name
  for name in time for A=B; do
    run --separate-stderr cmd_ws_run -- "$name" --version 'a b'
    [ "$status" -eq 0 ]
    [ "$output" = "${name}:[--version a b]" ]
  done
}

@test "cmd_ws_shell runs a command named like a reserved word or an assignment" {
  ws_quoting_fixture
  ws_command_name_fixtures

  local name
  for name in time for A=B; do
    run --separate-stderr cmd_ws_shell "$name" --version 'a b'
    [ "$status" -eq 0 ]
    [ "$output" = "${name}:[--version a b]" ]
  done
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
  [[ $output == *"No devcontainer to remove"* ]]
}

@test "cmd_ws_up passes args to devcontainer up" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock devcontainer 0 ""

  # The assertion needs the unspliced command, so forge-seed has to be absent.
  # A developer host that installs it would otherwise fail this test.
  local sanitized
  sanitized="$(sanitized_bin_excluding forge-seed)"

  PATH="${TEST_TMPDIR}/bin:${sanitized}" run cmd_ws_up -- --build-no-cache
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

@test "cmd_ws_reup regenerates the merged config fresh for a registered project" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"
  create_user_image_fixture python-dev
  git -C "$WORKSPACE_FOLDER" init -q
  git -C "$WORKSPACE_FOLDER" remote add origin "https://github.com/org/myproj.git"
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<'YAML'
org-myproj:
  devcontainer-manifest: python
YAML
  enable_mocks
  create_mock devcontainer 0 ""

  local gen
  gen="$(devcontainer_generated_path_for_manifest python)"

  run cmd_ws_reup
  [ "$status" -eq 0 ]
  [ -f "$gen" ]
  # Merge reflects the current layers with no separate generate step.
  [ "$(jq -r '.image' "$gen")" = "devimg/python-dev:latest" ]
  [[ $output != *"Config cache status:"* ]]
  assert_mock_called "devcontainer up --workspace-folder ${WORKSPACE_FOLDER} --config ${gen} --remove-existing-container"
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
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""

  TERM=xterm-256color COLORTERM=truecolor run cmd_ws_run -- codex
  [ "$status" -eq 0 ]
  assert_mock_called "--remote-env TERM=xterm-256color"
  assert_mock_called "--remote-env COLORTERM=truecolor"
}

@test "cmd_image_list prints discovered targets from user config dir" {
  create_user_image_fixture agents
  create_user_image_fixture python-dev

  run cmd_image_list
  [ "$status" -eq 0 ]
  [[ $output == *"agents"* ]]
  [[ $output == *"python-dev"* ]]
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

  run script -qec "env PATH='${PATH}' XDG_DATA_HOME='${XDG_DATA_HOME}' XDG_CONFIG_HOME='${XDG_CONFIG_HOME}' XDG_CACHE_HOME='${XDG_CACHE_HOME}' WORKSPACE_FOLDER='${WORKSPACE_FOLDER}' DCTL_LIB_DIR='${DCTL_LIB_DIR}' bash -lc 'set -euo pipefail; source \"${DCTL_LIB_DIR}/common.sh\"; source \"${DCTL_LIB_DIR}/auth.sh\"; source \"${DCTL_LIB_DIR}/image.sh\"; cmd_image_build --dry-run'" /dev/null
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

@test "cmd_image_build --full-rebuild honours an explicit target" {
  create_user_image_fixture agents
  create_user_image_fixture python-dev

  run cmd_image_build --dry-run --full-rebuild agents
  [ "$status" -eq 0 ]
  [[ $output == *"devimg/agents:latest"* ]]
  [[ $output != *"python-dev"* ]]
  [[ $output == *"--no-cache"* ]]
}

@test "cmd_image_build --full-rebuild with no target still builds all" {
  create_user_image_fixture agents
  create_user_image_fixture python-dev

  run cmd_image_build --dry-run --full-rebuild
  [ "$status" -eq 0 ]
  [[ $output == *"devimg/agents:latest"* ]]
  [[ $output == *"devimg/python-dev:latest"* ]]
}

# --- Managed image ordering ---

@test "cmd_image_build --all builds the family in dependency order" {
  create_image_family_fixture

  run cmd_image_build --dry-run --all
  [ "$status" -eq 0 ]
  [ "$(dry_run_build_order "$output")" = "base agents child-a child-b " ]
}

@test "cmd_image_build on one leaf builds its ancestors first" {
  create_image_family_fixture

  run cmd_image_build --dry-run child-a
  [ "$status" -eq 0 ]
  [ "$(dry_run_build_order "$output")" = "base agents child-a " ]
}

@test "_image_parents reads through a --platform flag and a stage alias" {
  create_user_image_dockerfile base 'FROM opensuse/tumbleweed'
  # shellcheck disable=SC2016  # the Dockerfile keeps $BUILDPLATFORM literal
  create_user_image_dockerfile runtime \
    'FROM --platform=$BUILDPLATFORM devimg/base:latest AS runtime'

  run _image_parents runtime
  [ "$status" -eq 0 ]
  [ "$output" = "base" ]
}

@test "cmd_image_build refuses a variable managed parent" {
  create_user_image_dockerfile base 'FROM opensuse/tumbleweed'
  # shellcheck disable=SC2016  # the Dockerfile keeps ${PARENT} literal
  create_user_image_dockerfile child 'FROM devimg/${PARENT}:latest'

  run cmd_image_build --dry-run child
  [ "$status" -ne 0 ]
  [[ $output == *"a variable reference cannot be ordered"* ]]
  [[ $output == *"child/Dockerfile:1"* ]]
}

@test "cmd_image_build refuses an unsupported managed parent spelling" {
  create_user_image_dockerfile base 'FROM opensuse/tumbleweed'
  create_user_image_dockerfile child 'FROM devimg/base:v2'

  run cmd_image_build --dry-run child
  [ "$status" -ne 0 ]
  [[ $output == *"unsupported managed parent"* ]]
  [[ $output == *"devimg/base:v2"* ]]
}

@test "cmd_image_build refuses a parent that has no Dockerfile" {
  create_user_image_dockerfile child-a 'FROM devimg/external:latest'

  run cmd_image_build --dry-run child-a
  [ "$status" -ne 0 ]
  [[ $output == *"parent \`external\` of \`child-a\` has no Dockerfile"* ]]
  [[ $output == *"${XDG_CONFIG_HOME}/dctl/images/external/Dockerfile"* ]]
  [[ $output != *"dctl deploy"* ]]
}

@test "cmd_image_build refuses a dependency cycle" {
  create_user_image_dockerfile a 'FROM devimg/b:latest'
  create_user_image_dockerfile b 'FROM devimg/a:latest'

  run cmd_image_build --dry-run --all
  [ "$status" -ne 0 ]
  [[ $output == *"image dependency cycle"* ]]
  [[ $output == *"a"* ]]
  [[ $output == *"b"* ]]
}

@test "cmd_image_build --dry-run orders the family without docker on PATH" {
  create_image_family_fixture
  local sanitized
  sanitized="$(sanitized_bin_excluding docker)"

  PATH="$sanitized" run cmd_image_build --dry-run --all
  [ "$status" -eq 0 ]
  [ "$(dry_run_build_order "$output")" = "base agents child-a child-b " ]
}

@test "cmd_image_build --full-rebuild pulls external bases and not managed parents" {
  create_image_family_fixture
  enable_mocks
  create_mock docker 0 ""

  run cmd_image_build --full-rebuild agents
  [ "$status" -eq 0 ]
  assert_mock_called "docker pull rust:1-slim"
  assert_mock_called "docker pull opensuse/tumbleweed"
  assert_mock_not_called "pull devimg/base:latest"
  assert_mock_not_called "--pull"
  assert_mock_called "docker buildx build --load --no-cache"
}

@test "cmd_image_build never pulls scratch or a same-file stage alias" {
  create_user_image_dockerfile base 'FROM opensuse/tumbleweed'
  create_user_image_dockerfile staged \
    'FROM scratch AS empty' \
    'FROM devimg/base:latest AS build' \
    'FROM empty'
  enable_mocks
  create_mock docker 0 ""

  run cmd_image_build --full-rebuild staged
  [ "$status" -eq 0 ]
  assert_mock_not_called "docker pull scratch"
  assert_mock_not_called "docker pull empty"
  assert_mock_not_called "docker pull devimg/base:latest"
}

@test "cmd_image_build skips descendants of a failed parent" {
  create_image_family_fixture
  enable_mocks
  # A stale devimg/base:latest is present (inspect succeeds), and its rebuild
  # fails. No descendant may be built on the stale tag.
  cat >"${TEST_TMPDIR}/bin/docker" <<EOF
#!/usr/bin/env bash
printf '%s\n' "docker \$*" >>"${TEST_TMPDIR}/mock_calls.log"
if [[ "\$*" == *"-t devimg/base:latest"* ]]; then
  exit 1
fi
exit 0
EOF
  chmod +x "${TEST_TMPDIR}/bin/docker"

  run cmd_image_build --all
  [ "$status" -ne 0 ]
  [[ $output == *"blocked by failed parent base"* ]]
  [[ $output == *"Failed to build: base"* ]]
  assert_mock_not_called "-t devimg/agents:latest"
  assert_mock_not_called "-t devimg/child-a:latest"
  assert_mock_not_called "-t devimg/child-b:latest"
}

@test "cmd_init errors when the user config has no devcontainer manifest" {
  run cmd_init
  [ "$status" -ne 0 ]
  [[ $output == *"No devcontainer manifests in ${XDG_CONFIG_HOME}/dctl/devcontainer"* ]]
  [[ $output == *"docs/examples/"* ]]
  [[ $output != *"dctl deploy"* ]]
}

@test "cmd_init --help only documents slim flags" {
  run cmd_init --help
  [ "$status" -eq 0 ]
  [[ $output == *"--devcontainer"* ]]
  [[ $output != *"--force"* ]]
  [[ $output != *"--image"* ]]
  [[ $output != *"--deploy-only"* ]]
  [[ $output != *"--pick-only"* ]]
  [[ $output != *"--reset"* ]]
}

@test "cmd_init rejects an unknown devcontainer" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"

  run cmd_init --devcontainer missing
  [ "$status" -ne 0 ]
  [[ $output == *"Unknown devcontainer: missing"* ]]
}

@test "cmd_test fails with init guidance when config is missing" {
  run cmd_test
  [ "$status" -ne 0 ]
  [[ $output == *"Run 'dctl init' or pass --config"* ]]
}

@test "cmd_test fails when devcontainer command is missing" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{\n  "image": "devimg/python-dev:latest"\n}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock docker 0 "container123"
  local sanitized
  sanitized="$(sanitized_bin_excluding devcontainer)"
  PATH="${TEST_TMPDIR}/bin:${sanitized}" run cmd_test
  [ "$status" -ne 0 ]
  [[ $output == *"Missing required command: devcontainer"* ]]
}

@test "cmd_test builds managed images before starting the devcontainer" {
  create_user_image_fixture python-dev
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{\n  "image": "devimg/python-dev:latest"\n}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock docker 0 "container123"
  create_mock devcontainer 0 ""

  run cmd_test
  [ "$status" -eq 0 ]
  assert_mock_called "docker buildx build"
  assert_mock_called "devcontainer up --workspace-folder ${WORKSPACE_FOLDER} --config"
  assert_mock_called "devcontainer exec --workspace-folder ${WORKSPACE_FOLDER} --config"
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
@test "root help lists init and test, and no deploy" {
  run env XDG_DATA_HOME="$XDG_DATA_HOME" HOME="${TEST_TMPDIR}/home" \
    bash "${BATS_TEST_DIRNAME}/../bin/dctl" help
  [ "$status" -eq 0 ]
  [[ $output == *"init"* ]]
  [[ $output == *"test"* ]]
  [[ $output != *"deploy"* ]]
}

# bats test_tags=integration
@test "dctl deploy fails as an unknown command" {
  run env XDG_DATA_HOME="$XDG_DATA_HOME" HOME="${TEST_TMPDIR}/home" \
    bash "${BATS_TEST_DIRNAME}/../bin/dctl" deploy --all
  [ "$status" -ne 0 ]
  [[ $output == *"Unknown command group: deploy"* ]]
}

# bats test_tags=integration
@test "make install installs bin, lib, and schemas, and no seed" {
  local bin_dir data_dir lib_dir
  bin_dir="${TEST_TMPDIR}/bin-install"
  data_dir="${TEST_TMPDIR}/data-home/dctl"
  lib_dir="${TEST_TMPDIR}/lib/dctl"

  run make -C "${BATS_TEST_DIRNAME}/.." install \
    BIN_DIR="$bin_dir" DATA_DIR="$data_dir" LIB_DIR="$lib_dir"
  [ "$status" -eq 0 ]

  [ -x "${bin_dir}/dctl" ]
  [ -f "${lib_dir}/common.sh" ]
  [ -f "${lib_dir}/init.sh" ]
  [ ! -e "${lib_dir}/deploy.sh" ]
  [ -f "${data_dir}/schemas/compose.schema.yaml" ]
  [ -f "${data_dir}/schemas/projects.schema.yaml" ]
  [ ! -e "${data_dir}/images" ]
  [ ! -e "${data_dir}/devcontainers" ]
}

# bats test_tags=integration
@test "make uninstall removes the seed files that an older release installed" {
  local bin_dir data_dir lib_dir
  bin_dir="${TEST_TMPDIR}/bin-install"
  data_dir="${TEST_TMPDIR}/data-home/dctl"
  lib_dir="${TEST_TMPDIR}/lib/dctl"
  run make -C "${BATS_TEST_DIRNAME}/.." install \
    BIN_DIR="$bin_dir" DATA_DIR="$data_dir" LIB_DIR="$lib_dir"
  [ "$status" -eq 0 ]
  # What an older release left behind.
  mkdir -p "${data_dir}/images/agents" "${data_dir}/images/zig-dev" \
    "${data_dir}/devcontainers/agents" "${data_dir}/devcontainers/general"
  touch "${data_dir}/images/agents/Dockerfile" "${data_dir}/images/zig-dev/zig-zls-init" \
    "${data_dir}/devcontainers/agents/devcontainer.json" \
    "${data_dir}/devcontainers/agents/seccomp-bwrap.json" \
    "${data_dir}/devcontainers/general/devcontainer.json" \
    "${data_dir}/devcontainers/general.yaml" "${data_dir}/devcontainers/README.md" \
    "${lib_dir}/deploy.sh"

  run make -C "${BATS_TEST_DIRNAME}/.." uninstall \
    BIN_DIR="$bin_dir" DATA_DIR="$data_dir" LIB_DIR="$lib_dir"
  [ "$status" -eq 0 ]
  [ ! -e "${bin_dir}/dctl" ]
  [ ! -e "$lib_dir" ]
  [ ! -e "$data_dir" ]
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
  create_mock devcontainer 0 ""

  run cmd_ws_up
  [ "$status" -eq 0 ]
  assert_mock_called "--mount type=bind,source=${main_repo}/.git,target=${main_repo}/.git"
}

# --- Forge auth forwarding: config-dir paths, never tokens ---

# forge-seed mock: records the call, materializes the scope dir, honours
# --print-dir. The seeding itself belongs to nix-secrets, not dctl.
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
dir="${TEST_TMPDIR}/seed/\${scope}"
mkdir -p "\$dir/gh" "\$dir/glab-cli"
[[ \$print_dir == true ]] && printf '%s\n' "\$dir"
exit 0
MOCK
  chmod +x "${TEST_TMPDIR}/bin/forge-seed"
}

@test "cmd_ws_shell forwards config-dir paths, never a token" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""
  _write_forge_seed_mock
  export GH_TOKEN="ghp_testXYZ"
  export GITLAB_TOKEN="glpat_testABC"

  run cmd_ws_shell
  [ "$status" -eq 0 ]
  assert_mock_called "forge-seed --scope workspace --print-dir"
  assert_mock_called "--remote-env GH_CONFIG_DIR=/run/forge-auth/gh"
  assert_mock_called "--remote-env GLAB_CONFIG_DIR=/run/forge-auth/glab-cli"
  assert_mock_not_called "--remote-env GH_TOKEN"
  assert_mock_not_called "--remote-env GITLAB_TOKEN"
  assert_mock_not_called "ghp_testXYZ"
  assert_mock_not_called "glpat_testABC"
}

@test "cmd_ws_shell forwards config-dir paths even when forge-seed is absent" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""

  run cmd_ws_shell
  [ "$status" -eq 0 ]
  assert_mock_called "--remote-env GH_CONFIG_DIR=/run/forge-auth/gh"
  assert_mock_called "--remote-env GLAB_CONFIG_DIR=/run/forge-auth/glab-cli"
  assert_mock_not_called "--remote-env GH_TOKEN"
  assert_mock_not_called "--remote-env GITLAB_TOKEN"
}

@test "cmd_ws_shell forwards no SSH_AUTH_SOCK when the host has no agent" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock docker 0 "running"
  create_mock devcontainer 0 ""

  run cmd_ws_shell
  [ "$status" -eq 0 ]
  assert_mock_not_called "SSH_AUTH_SOCK"
}

@test "cmd_ws_up mounts the forge auth seed dir" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock devcontainer 0 ""
  _write_forge_seed_mock

  run cmd_ws_up
  [ "$status" -eq 0 ]
  assert_mock_called "--mount type=bind,source=${TEST_TMPDIR}/seed/workspace,target=/run/forge-auth"
  assert_mock_not_called "--remote-env GH_TOKEN"
}

@test "cmd_ws_reup mounts the forge auth seed dir" {
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "devimg/agents:latest"}\n' >"$(workspace_devcontainer_file)"
  enable_mocks
  create_mock docker 0 ""
  create_mock devcontainer 0 ""
  _write_forge_seed_mock

  run cmd_ws_reup
  [ "$status" -eq 0 ]
  assert_mock_called "--mount type=bind,source=${TEST_TMPDIR}/seed/workspace,target=/run/forge-auth"
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
    bash -c 'source "'"$DCTL_LIB_DIR"'/common.sh"; source "'"$DCTL_LIB_DIR"'/config.sh"; resolve_devcontainer_config'
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
    bash -c 'source "'"$DCTL_LIB_DIR"'/common.sh"; source "'"$DCTL_LIB_DIR"'/config.sh"; resolve_devcontainer_config'
  [ "$status" -ne 0 ]
  [[ $output == *"No devcontainer config found"* ]]
}

# --- Deploy / init / Dockerfile resolution ---

@test "resolve_dockerfile fails when only a stale seed image exists" {
  create_stale_seed_image_fixture agents

  run resolve_dockerfile agents
  [ "$status" -ne 0 ]
}

@test "resolve_dockerfile returns user config path" {
  create_user_image_fixture agents

  run resolve_dockerfile agents
  [ "$status" -eq 0 ]
  [[ $output == *"xdg-config"* ]]
}

@test "resolve_dockerfile fails for unknown target" {
  run resolve_dockerfile nonexistent
  [ "$status" -ne 0 ]
}

@test "discover_image_targets includes user image targets" {
  create_user_image_fixture custom-img
  create_stale_seed_image_fixture agents

  run discover_image_targets
  [ "$status" -eq 0 ]
  [[ $output == *"custom-img"* ]]
  [[ $output != *"agents"* ]]
}

@test "discover_image_targets ignores stale seed images" {
  create_stale_seed_image_fixture agents

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

@test "discover_config_layers errors when manifest is missing" {
  run discover_config_layers missing
  [ "$status" -ne 0 ]
  [[ $output == *"No manifest found for 'missing'"* ]]
}

@test "generate_devcontainer works with manifest-defined layers" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"

  run generate_devcontainer python
  [ "$status" -eq 0 ]

  local deployed
  deployed="$(devcontainer_generated_path_for_manifest python)"
  [ "${lines[0]}" = "$deployed" ]
  [ -f "$deployed" ]
  [ "$(jq -r '.remoteUser' "$deployed")" = "testuser" ]
  [ "$(jq -r '.init' "$deployed")" = "true" ]
  [ "$(jq -r '.shutdownAction' "$deployed")" = "none" ]
  [ "$(jq -r '.image' "$deployed")" = "devimg/python-dev:latest" ]
}

@test "generate_devcontainer merges multiple manifest layers with correct ordering" {
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

  run generate_devcontainer python
  [ "$status" -eq 0 ]

  local deployed
  deployed="$(devcontainer_generated_path_for_manifest python)"
  [ -f "$deployed" ]
  [ "$(jq -r '.name' "$deployed")" = "top" ]
  [ "$(jq -r '.containerEnv.LEVEL' "$deployed")" = "top" ]
  [ "$(jq '.mounts | length' "$deployed")" = "2" ]
  [ "$(jq -r '.mounts[0].target' "$deployed")" = "/middle" ]
  [ "$(jq -r '.mounts[1].target' "$deployed")" = "/top" ]
}

@test "generate_devcontainer regenerates a fresh artifact every call" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"

  local deployed
  deployed="$(devcontainer_generated_path_for_manifest python)"

  run generate_devcontainer python
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$deployed" ]
  [ "$(jq -r '.image' "$deployed")" = "devimg/python-dev:latest" ]

  # A layer edit is reflected on the next call with no freshness gate.
  printf '{\n  "image": "devimg/python-dev:latest",\n  "name": "edited"\n}\n' \
    >"${XDG_CONFIG_HOME}/dctl/devcontainer/python/devcontainer.json"
  run generate_devcontainer python
  [ "$status" -eq 0 ]
  [ "$(jq -r '.name' "$deployed")" = "edited" ]
}

@test "cmd_init reads only user config and ignores stale seed templates" {
  create_stale_seed_template_fixture python "devimg/rust-dev:latest"
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"
  create_user_image_fixture python-dev
  enable_mocks
  create_mock docker 0 ""
  # shellcheck disable=SC2329
  cmd_test() { :; }

  run cmd_init --devcontainer python
  [ "$status" -eq 0 ]
  [ "$(jq -r '.image' "$(devcontainer_generated_path_for_manifest python)")" = "devimg/python-dev:latest" ]
}

@test "cmd_init errors when a managed image has no Dockerfile" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"

  run cmd_init --devcontainer python
  [ "$status" -ne 0 ]
  [[ $output == *"Image 'python-dev' has no Dockerfile. Add ${XDG_CONFIG_HOME}/dctl/images/python-dev/Dockerfile"* ]]
}

@test "cmd_init calls cmd_image_build when managed image is missing locally" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"
  create_user_image_fixture python-dev
  enable_mocks
  create_mock docker 1 ""
  # shellcheck disable=SC2329
  cmd_image_build() { echo "CMD_IMAGE_BUILD_CALLED $*" >>"${TEST_TMPDIR}/mock_calls.log"; }
  # shellcheck disable=SC2329
  cmd_test() { :; }

  run cmd_init --devcontainer python
  [ "$status" -eq 0 ]
  assert_mock_called "docker image inspect devimg/python-dev:latest"
  assert_mock_called "CMD_IMAGE_BUILD_CALLED python-dev"
}

@test "cmd_init skips build when managed image already exists locally" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"
  create_user_image_fixture python-dev
  enable_mocks
  create_mock docker 0 ""
  # shellcheck disable=SC2329
  cmd_image_build() { echo "CMD_IMAGE_BUILD_CALLED $*" >>"${TEST_TMPDIR}/mock_calls.log"; }
  # shellcheck disable=SC2329
  cmd_test() { :; }

  run cmd_init --devcontainer python
  [ "$status" -eq 0 ]
  assert_mock_called "docker image inspect devimg/python-dev:latest"
  assert_mock_not_called "CMD_IMAGE_BUILD_CALLED python-dev"
}

@test "cmd_init registers manifest name and produces generated config" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"
  create_user_image_fixture python-dev
  enable_mocks
  create_mock docker 0 ""
  # shellcheck disable=SC2329
  cmd_test() { :; }

  run cmd_init --devcontainer python
  [ "$status" -eq 0 ]

  local deployed
  deployed="$(devcontainer_generated_path_for_manifest python)"
  local registry="${XDG_CONFIG_HOME}/dctl/projects.yaml"
  local canonical
  canonical="$(resolve_canonical_project_name)"

  [ -f "$deployed" ]
  [ -f "$registry" ]
  [ "$(yq -r ".\"${canonical}\"[\"devcontainer-manifest\"]" "$registry")" = "python" ]
  [ "$(yq -r ".\"${canonical}\".dockerfile // \"\"" "$registry")" = "" ]
  [ "$(yq -r ".\"${canonical}\".image // \"\"" "$registry")" = "" ]
  [ "$(yq -r ".\"${canonical}\" | has(\"sibling_discovery\")" "$registry")" = "false" ]
}

@test "cmd_init auto-migrates the registry even when unrelated entries are legacy" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"
  create_user_image_fixture python-dev
  enable_mocks
  create_mock docker 0 ""
  local canonical
  canonical="$(resolve_canonical_project_name)"
  local registry="${XDG_CONFIG_HOME}/dctl/projects.yaml"
  # Active project has a legacy entry; an unrelated project also still has
  # one. A normal init must auto-migrate the unrelated entry's legacy
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
  cmd_test() { :; }

  run cmd_init --devcontainer python
  [ "$status" -eq 0 ]
  [ "$(yq -r ".\"${canonical}\"[\"devcontainer-manifest\"]" "$registry")" = "python" ]
  [ "$(yq -r ".\"${canonical}\" | has(\"devcontainer\")" "$registry")" = "false" ]
  # Unrelated project's manifest stem is preserved by deriving from
  # basename(dirname(legacy path)), not silently unregistered.
  [ "$(yq -r '.["other-project"]["devcontainer-manifest"]' "$registry")" = "general" ]
  [ "$(yq -r '.["other-project"] | has("devcontainer")' "$registry")" = "false" ]
  [ "$(yq -r '.["other-project"].sibling_discovery' "$registry")" = "false" ]
}

@test "cmd_init auto-scrubs legacy devcontainer key for the active project" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"
  create_user_image_fixture python-dev
  enable_mocks
  create_mock docker 0 ""
  local canonical
  canonical="$(resolve_canonical_project_name)"
  local registry="${XDG_CONFIG_HOME}/dctl/projects.yaml"
  # Seed a registry that still uses the legacy `devcontainer:` key for the
  # current project. The switching lookup tolerates the legacy entry and
  # register_project_defaults scrubs it during the normal write.
  cat >"$registry" <<YAML
${canonical}:
  devcontainer: \$HOME/cache/path/devcontainer.json
  sibling_discovery: false
YAML
  # shellcheck disable=SC2329
  cmd_test() { :; }

  run cmd_init --devcontainer python
  [ "$status" -eq 0 ]
  [ "$(yq -r ".\"${canonical}\"[\"devcontainer-manifest\"]" "$registry")" = "python" ]
  [ "$(yq -r ".\"${canonical}\" | has(\"devcontainer\")" "$registry")" = "false" ]
  [ "$(yq -r ".\"${canonical}\".sibling_discovery" "$registry")" = "false" ]
}

@test "cmd_init preserves explicit sibling_discovery: false" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"
  create_user_image_fixture python-dev
  enable_mocks
  create_mock docker 0 ""
  local canonical
  canonical="$(resolve_canonical_project_name)"
  local registry="${XDG_CONFIG_HOME}/dctl/projects.yaml"
  cat >"$registry" <<YAML
${canonical}:
  devcontainer-manifest: rust
  sibling_discovery: false
YAML
  # shellcheck disable=SC2329
  cmd_test() { :; }

  run cmd_init --devcontainer python
  [ "$status" -eq 0 ]
  [ "$(yq -r ".\"${canonical}\"[\"devcontainer-manifest\"]" "$registry")" = "python" ]
  [ "$(yq -r ".\"${canonical}\".dockerfile // \"\"" "$registry")" = "" ]
  [ "$(yq -r ".\"${canonical}\".image // \"\"" "$registry")" = "" ]
  [ "$(yq -r ".\"${canonical}\".sibling_discovery" "$registry")" = "false" ]
}

@test "cmd_init switches registered manifest when a different deployed devcontainer is selected" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"
  create_user_devcontainer_fixture rust "devimg/rust-dev:latest"
  create_user_image_fixture python-dev
  create_user_image_fixture rust-dev
  enable_mocks
  create_mock docker 0 ""
  # shellcheck disable=SC2329
  cmd_test() { :; }

  run cmd_init --devcontainer python
  [ "$status" -eq 0 ]

  local canonical
  canonical="$(resolve_canonical_project_name)"
  local registry="${XDG_CONFIG_HOME}/dctl/projects.yaml"

  run cmd_init --devcontainer rust
  [ "$status" -eq 0 ]
  [[ $output == *"Switching project"* ]]
  [ "$(yq -r ".\"${canonical}\"[\"devcontainer-manifest\"]" "$registry")" = "rust" ]
}

@test "cmd_init invokes cmd_test and reports the result in the summary" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"
  create_user_image_fixture python-dev
  enable_mocks
  create_mock docker 0 ""
  # shellcheck disable=SC2329
  cmd_test() { echo "CMD_TEST_CALLED" >>"${TEST_TMPDIR}/mock_calls.log"; }

  run cmd_init --devcontainer python
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
  create_mock docker 0 ""
  # shellcheck disable=SC2329
  cmd_test() { return 1; }

  run cmd_init --devcontainer python
  [ "$status" -ne 0 ]
  [[ $output == *"Smoke test: failed"* ]]
}

@test "cmd_init accepts external images without trying to build" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "ghcr.io/acme/project:latest"
  # shellcheck disable=SC2329
  cmd_image_build() { echo "CMD_IMAGE_BUILD_CALLED $*" >>"${TEST_TMPDIR}/mock_calls.log"; }
  # shellcheck disable=SC2329
  cmd_test() { :; }

  run cmd_init --devcontainer python
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

@test "cmd_test skips devcontainer up when a bind mount source is missing" {
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
  create_mock docker 0 "container123"
  create_mock devcontainer 0 ""

  run cmd_test
  [ "$status" -ne 0 ]
  [[ $output == *"Missing bind mount source(s) on host"* ]]
  [[ $output == *"$missing"* ]]
  assert_mock_not_called "devcontainer up"
}
