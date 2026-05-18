#!/usr/bin/env bats

# bats file_tags=unit

load test_helper

source_net() {
  local repo_root
  repo_root="${BATS_TEST_DIRNAME}/.."
  readonly DCTL_LIB_DIR="${repo_root}/lib/dctl"
  set -euo pipefail
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/_lib/source.sh"
  __dctl_require _lib/log.sh
  __dctl_require _lib/paths.sh
  __dctl_require _lib/json/strip_comments.sh
  __dctl_require _lib/json/validate_layer.sh
  __dctl_require _lib/json/merge_runargs.sh
  __dctl_require _lib/json/merge_configs.sh
  __dctl_require _lib/registry/validate_manifest.sh
  __dctl_require _lib/registry/read_manifest_layers.sh
  __dctl_require _lib/registry/lookup_manifest.sh
  __dctl_require _lib/workspace/canonical_name.sh
  __dctl_require _lib/workspace/resolve_config.sh
  __dctl_require commands/net/_default_allowlist.sh
  __dctl_require commands/net/_user_allowlist.sh
  __dctl_require commands/net/_compose.sh
  __dctl_require commands/net/allow.sh
  __dctl_require commands/net/show.sh
  __dctl_require commands/init/_generate_cache.sh
}

create_user_base_layer_fixture() {
  mkdir -p "${XDG_CONFIG_HOME}/dctl/devcontainer/base"
  cat >"${XDG_CONFIG_HOME}/dctl/devcontainer/base/devcontainer.json" <<'EOF'
{
  "remoteUser": "dev",
  "init": true
}
EOF
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
  mkdir -p "${XDG_DATA_HOME}/dctl" "${XDG_CONFIG_HOME}/dctl" "${XDG_CACHE_HOME}/dctl" "$WORKSPACE_FOLDER"
  source_net
  create_user_base_layer_fixture
  create_general_leaf_fixture
  create_user_manifest_fixture general base general
  setup_workspace_git_fixture
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<'EOF'
foo-bar:
  devcontainer-manifest: general
EOF
}

teardown() {
  teardown_test_fixtures
}

@test "net_compose_allowlist returns sorted defaults plus git remotes plus user entries" {
  DCTL_NET_MANIFEST_HINT=general run net_compose_allowlist "$WORKSPACE_FOLDER"
  [ "$status" -eq 0 ]

  local expected
  expected="$(
    cat <<'EOF'
*.githubusercontent.com
*.gitlab.io
*.googleapis.com
api.anthropic.com
api.openai.com
crates.io
download.opensuse.org
example.net
files.pythonhosted.org
foo.example
github.com
gitlab.com
index.crates.io
pypi.org
registry.npmjs.org
zed.example
EOF
  )"
  [ "$output" = "$expected" ]
}

@test "cmd_net_show prints default git-remote and user origin annotations" {
  DCTL_NET_MANIFEST_HINT=general run cmd_net_show
  [ "$status" -eq 0 ]
  [[ $output == *$'default\tapi.anthropic.com'* ]]
  [[ $output == *$'default\tgithub.com'* ]]
  [[ $output == *$'git-remote\texample.net'* ]]
  [[ $output == *$'user\tfoo.example'* ]]
  [[ $output == *$'user\tzed.example'* ]]
}
