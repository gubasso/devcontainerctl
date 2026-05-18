#!/usr/bin/env bats

# bats file_tags=integration

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

create_user_devcontainer_fixture() {
  local name="$1"
  local image="$2"
  mkdir -p "${XDG_CONFIG_HOME}/dctl/devcontainer/${name}"
  printf '{\n  "image": "%s"\n}\n' "$image" >"${XDG_CONFIG_HOME}/dctl/devcontainer/${name}/devcontainer.json"
  if [[ $name != "base" ]]; then
    create_user_manifest_fixture "$name" base "$name"
  fi
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

create_general_leaf_fixture() {
  mkdir -p "${XDG_CONFIG_HOME}/dctl/devcontainer/general"
  cat >"${XDG_CONFIG_HOME}/dctl/devcontainer/general/devcontainer.json" <<'EOF'
{
  "image": "devimg/agents:latest",
  "network": {
    "allow": ["foo.example", "zed.example"]
  }
}
EOF
}

setup_workspace_git_fixture() {
  git -C "$WORKSPACE_FOLDER" init -q
  git -C "$WORKSPACE_FOLDER" remote add origin "https://github.com/foo/bar.git"
  git -C "$WORKSPACE_FOLDER" remote add mirror "git@example.net:baz/qux.git"
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
  create_mock gh 1
  create_mock glab 1
  enable_mocks
  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES 2>/dev/null || true
}

teardown() {
  teardown_test_fixtures
}

@test "cmd_ws_reup regenerates cached config when a layer mtime is newer" {
  create_user_base_layer_fixture
  create_user_devcontainer_fixture python "devimg/python-dev:latest"

  run generate_cached_devcontainer python
  [ "$status" -eq 0 ]
  local cached="${XDG_CACHE_HOME}/dctl/devcontainer/python/devcontainer.json"
  [ -f "$cached" ]

  touch -d "+1 second" "${XDG_CONFIG_HOME}/dctl/devcontainer/python/devcontainer.json"

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

  touch -d "+1 second" "${XDG_CONFIG_HOME}/dctl/devcontainer/python/devcontainer.json"

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

  create_mock podman 0 "container123"

  DCTL_CLI_CONFIG="$cached" run cmd_ws_reup
  [ "$status" -eq 0 ]
  [[ $output == *"Config cache status: cached"* ]]
  assert_mock_called "podman rm -f"
  assert_mock_called "podman run --runtime krun --detach"
}

@test "cmd_net_allow appends to the leaf devcontainer and regenerates cache" {
  create_user_base_layer_fixture
  create_general_leaf_fixture
  create_user_manifest_fixture general base general
  setup_workspace_git_fixture
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<'EOF'
foo-bar:
  devcontainer-manifest: general
EOF

  run generate_cached_devcontainer general true
  [ "$status" -eq 0 ]
  local cached="${XDG_CACHE_HOME}/dctl/devcontainer/general/devcontainer.json"
  [ -f "$cached" ]
  touch -d '1970-01-01 00:00:01 UTC' "$cached"
  local before_mtime
  before_mtime="$(stat -c '%Y' "$cached")"

  run cmd_net_allow foo2.example
  [ "$status" -eq 0 ]
  [ "$(jq -r '.network.allow[]' "${XDG_CONFIG_HOME}/dctl/devcontainer/general/devcontainer.json" | grep -c '^foo2.example$')" -eq 1 ]
  [ "$(jq -r '.network.allow[]' "$cached" | grep -c '^foo2.example$')" -eq 1 ]
  [ "$(stat -c '%Y' "$cached")" -gt "$before_mtime" ]
  [[ $output == *$'user\tfoo2.example'* ]]
}
