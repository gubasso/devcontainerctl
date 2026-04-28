#!/usr/bin/env bats

# bats file_tags=unit

load test_helper

setup() {
  setup_test_fixtures
  export XDG_DATA_HOME="${TEST_TMPDIR}/xdg-data"
  export XDG_CONFIG_HOME="${TEST_TMPDIR}/xdg-config"
  export WORKSPACE_FOLDER="${TEST_TMPDIR}/workspace"
  mkdir -p "${XDG_DATA_HOME}/dctl/images" "${XDG_DATA_HOME}/dctl/schemas" \
    "${XDG_CONFIG_HOME}/dctl" "$WORKSPACE_FOLDER"
  unset DCTL_CONFIG DCTL_CLI_CONFIG 2>/dev/null || true

  local repo_root="${BATS_TEST_DIRNAME}/.."
  export DCTL_LIB_DIR="${repo_root}/lib/dctl"
  set -euo pipefail
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/common.sh"
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/config.sh"

  # Copy schema for validation tests
  cp "${BATS_TEST_DIRNAME}/../schemas/projects.schema.yaml" \
    "${XDG_DATA_HOME}/dctl/schemas/projects.schema.yaml"

  # Clear git env leaked by pre-commit
  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES 2>/dev/null || true
}

teardown() {
  teardown_test_fixtures
}

# Helper to run functions with a custom WORKSPACE_FOLDER (avoids readonly issue)
run_with_workspace() {
  local wf="$1"
  shift
  run env WORKSPACE_FOLDER="$wf" XDG_DATA_HOME="$XDG_DATA_HOME" \
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    bash -c 'source "'"$DCTL_LIB_DIR"'/common.sh"; source "'"$DCTL_LIB_DIR"'/config.sh"; '"$*"
}

# --- Canonical name derivation ---

# bats test_tags=integration
@test "resolve_canonical_project_name from https remote" {
  git -C "$WORKSPACE_FOLDER" init -q
  git -C "$WORKSPACE_FOLDER" remote add origin "https://github.com/org/repo.git"

  run resolve_canonical_project_name
  [ "$status" -eq 0 ]
  [ "$output" = "org-repo" ]
}

# bats test_tags=integration
@test "resolve_canonical_project_name from ssh remote" {
  git -C "$WORKSPACE_FOLDER" init -q
  git -C "$WORKSPACE_FOLDER" remote add origin "git@github.com:org/repo.git"

  run resolve_canonical_project_name
  [ "$status" -eq 0 ]
  [ "$output" = "org-repo" ]
}

@test "resolve_canonical_project_name falls back to basename" {
  local wf="${TEST_TMPDIR}/myproject"
  mkdir -p "$wf"

  run_with_workspace "$wf" resolve_canonical_project_name
  [ "$status" -eq 0 ]
  [ "$output" = "myproject" ]
}

@test "resolve_canonical_project_name strips work-clone suffix" {
  local wf="${TEST_TMPDIR}/repo.42-add-auth"
  mkdir -p "$wf"

  run_with_workspace "$wf" resolve_canonical_project_name
  [ "$status" -eq 0 ]
  [ "$output" = "repo" ]
}

# --- Registry parsing ---

@test "registry lookup returns devcontainer path for known project" {
  local config="${TEST_TMPDIR}/custom.json"
  printf '{"image": "custom"}\n' >"$config"
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<YAML
test-project:
  devcontainer: ${config}
YAML

  run _registry_lookup_devcontainer "test-project"
  [ "$status" -eq 0 ]
  [ "$output" = "$config" ]
}

@test 'registry lookup expands $HOME in devcontainer path' {
  local config="${HOME}/some/config.json"
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<'YAML'
test-project:
  devcontainer: $HOME/some/config.json
YAML

  run _registry_lookup_devcontainer "test-project"
  [ "$status" -eq 0 ]
  [ "$output" = "$config" ]
}

@test "registry lookup returns empty for unknown project" {
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<YAML
other-project:
  devcontainer: /some/path.json
YAML

  run _registry_lookup_devcontainer "unknown-project"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "registry lookup returns empty when file does not exist" {
  run _registry_lookup_devcontainer "any-project"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "registry sibling_discovery defaults to true" {
  run _registry_lookup_sibling_discovery "any-project"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "registry sibling_discovery returns false when set" {
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<YAML
my-repo:
  sibling_discovery: false
YAML

  run _registry_lookup_sibling_discovery "my-repo"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "registry validation rejects dockerfile key" {
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<'YAML'
proj:
  dockerfile: python-dev
YAML

  run _registry_lookup_devcontainer "proj"
  [ "$status" -ne 0 ]
  [[ $output == *"Unrecognized key"* || $output == *"additional properties"* || $output == *"ailed"* ]]
}

@test "registry validation rejects image key" {
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<'YAML'
proj:
  image: devimg/foo:latest
YAML

  run _registry_lookup_devcontainer "proj"
  [ "$status" -ne 0 ]
  [[ $output == *"Unrecognized key"* || $output == *"additional properties"* || $output == *"ailed"* ]]
}

# --- Schema validation ---

@test "registry validation accepts valid file" {
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<YAML
my-repo:
  devcontainer: /path/to/config.json
YAML

  run _validate_registry "${XDG_CONFIG_HOME}/dctl/projects.yaml"
  [ "$status" -eq 0 ]
}

@test "registry validation accepts explicit sibling_discovery false" {
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<YAML
my-repo:
  devcontainer: /path/to/config.json
  sibling_discovery: false
YAML

  run _validate_registry "${XDG_CONFIG_HOME}/dctl/projects.yaml"
  [ "$status" -eq 0 ]
}

@test "registry validation rejects invalid YAML" {
  printf 'not: valid: yaml: [broken\n' >"${XDG_CONFIG_HOME}/dctl/projects.yaml"

  run _validate_registry "${XDG_CONFIG_HOME}/dctl/projects.yaml"
  [ "$status" -ne 0 ]
  # check-jsonschema says "Failed" or "failed"; yq fallback says "Invalid YAML"
  [[ $output == *"Invalid YAML"* || $output == *"ailed"* ]]
}

@test "registry validation rejects unrecognized keys" {
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<YAML
my-repo:
  unknown_key: value
YAML

  run _validate_registry "${XDG_CONFIG_HOME}/dctl/projects.yaml"
  [ "$status" -ne 0 ]
  # check-jsonschema reports "Additional properties"; yq fallback says "Unrecognized key"
  [[ $output == *"Unrecognized key"* || $output == *"additional properties"* || $output == *"ailed"* ]]
}

@test "registry validation rejects non-boolean sibling_discovery" {
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<YAML
my-repo:
  sibling_discovery: "yes"
YAML

  run _validate_registry "${XDG_CONFIG_HOME}/dctl/projects.yaml"
  [ "$status" -ne 0 ]
  [[ $output == *"sibling_discovery"* ]]
}

@test "registry validation rejects non-string devcontainer" {
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<YAML
my-repo:
  devcontainer: 42
YAML

  run _validate_registry "${XDG_CONFIG_HOME}/dctl/projects.yaml"
  [ "$status" -ne 0 ]
  [[ $output == *"devcontainer"* ]]
}

@test "registry validation accepts empty file" {
  touch "${XDG_CONFIG_HOME}/dctl/projects.yaml"

  run _validate_registry "${XDG_CONFIG_HOME}/dctl/projects.yaml"
  [ "$status" -eq 0 ]
}

@test "registry validation accepts file with only whitespace" {
  printf '\n\n' >"${XDG_CONFIG_HOME}/dctl/projects.yaml"

  run _validate_registry "${XDG_CONFIG_HOME}/dctl/projects.yaml"
  [ "$status" -eq 0 ]
}

# --- Registry-backed resolution ---

@test "registry devcontainer overrides local config" {
  # Local config exists
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "local"}\n' >"$(workspace_devcontainer_file)"

  # Registry points to a different config
  local reg_config="${TEST_TMPDIR}/registry-config.json"
  printf '{"image": "registry"}\n' >"$reg_config"

  # Need canonical name for the current workspace
  local canonical
  canonical="$(resolve_canonical_project_name)"
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<YAML
${canonical}:
  devcontainer: ${reg_config}
YAML

  run resolve_devcontainer_config
  [ "$status" -eq 0 ]
  [[ $output == *"registry-config.json" ]]
}

# --- Sibling discovery opt-out ---

# bats test_tags=integration
@test "sibling discovery respects opt-out from registry" {
  local parent="${TEST_TMPDIR}/projects"
  local main_repo="${parent}/repo"
  local work_clone="${parent}/repo.42-feature"
  mkdir -p "$main_repo/.devcontainer" "$work_clone"
  printf '{"image": "sibling"}\n' >"$main_repo/.devcontainer/devcontainer.json"
  git -C "$main_repo" init -q

  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<YAML
repo:
  sibling_discovery: false
YAML

  run_with_workspace "$work_clone" resolve_work_clone_sibling
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "register_project_defaults creates registry from scratch" {
  local registry="${XDG_CONFIG_HOME}/dctl/projects.yaml"

  run register_project_defaults "proj-a" "/tmp/proj-a/devcontainer.json"
  [ "$status" -eq 0 ]
  [ -f "$registry" ]
  [ "$(yq -r '."proj-a".devcontainer' "$registry")" = "/tmp/proj-a/devcontainer.json" ]
  [ "$(yq -r '."proj-a" | has("dockerfile")' "$registry")" = "false" ]
  [ "$(yq -r '."proj-a" | has("image")' "$registry")" = "false" ]
  [ "$(yq -r '."proj-a" | has("sibling_discovery")' "$registry")" = "false" ]
}

@test 'register_project_defaults stores $HOME in devcontainer path' {
  local registry="${XDG_CONFIG_HOME}/dctl/projects.yaml"
  local home_path="${HOME}/config/devcontainer.json"

  run register_project_defaults "proj-home" "$home_path"
  [ "$status" -eq 0 ]
  [ -f "$registry" ]
  # Raw YAML should contain $HOME, not expanded path
  # shellcheck disable=SC2016
  [[ "$(yq -r '."proj-home".devcontainer' "$registry")" == '$HOME'* ]]
}

@test "register_project_defaults skips existing project with warning" {
  local registry="${XDG_CONFIG_HOME}/dctl/projects.yaml"
  cat >"$registry" <<'YAML'
proj-a:
  devcontainer: /tmp/original.json
  sibling_discovery: false
YAML

  run register_project_defaults "proj-a" "/tmp/new.json"
  [ "$status" -eq 0 ]
  [[ $output == *"already registered"* ]]
  [ "$(yq -r '."proj-a".devcontainer' "$registry")" = "/tmp/original.json" ]
  [ "$(yq -r '."proj-a".sibling_discovery' "$registry")" = "false" ]
}

@test "register_project_defaults with force updates existing project" {
  local registry="${XDG_CONFIG_HOME}/dctl/projects.yaml"
  cat >"$registry" <<'YAML'
proj-a:
  devcontainer: /tmp/original.json
  sibling_discovery: false
YAML

  run register_project_defaults "proj-a" "/tmp/new.json" "true"
  [ "$status" -eq 0 ]
  [ "$(yq -r '."proj-a".devcontainer' "$registry")" = "/tmp/new.json" ]
  [ "$(yq -r '."proj-a" | has("dockerfile")' "$registry")" = "false" ]
  [ "$(yq -r '."proj-a" | has("image")' "$registry")" = "false" ]
  [ "$(yq -r '."proj-a".sibling_discovery' "$registry")" = "false" ]
}

@test "register_project_defaults with force strips default sibling_discovery" {
  local registry="${XDG_CONFIG_HOME}/dctl/projects.yaml"
  cat >"$registry" <<'YAML'
proj-a:
  devcontainer: /tmp/original.json
  sibling_discovery: true
YAML

  run register_project_defaults "proj-a" "/tmp/new.json" "true"
  [ "$status" -eq 0 ]
  [ "$(yq -r '."proj-a".devcontainer' "$registry")" = "/tmp/new.json" ]
  [ "$(yq -r '."proj-a" | has("dockerfile")' "$registry")" = "false" ]
  [ "$(yq -r '."proj-a" | has("image")' "$registry")" = "false" ]
  [ "$(yq -r '."proj-a" | has("sibling_discovery")' "$registry")" = "false" ]
}

@test "register_project_defaults appends to existing registry" {
  local registry="${XDG_CONFIG_HOME}/dctl/projects.yaml"
  cat >"$registry" <<'YAML'
proj-a:
  devcontainer: /tmp/proj-a.json
YAML

  run register_project_defaults "proj-b" "/tmp/proj-b.json"
  [ "$status" -eq 0 ]
  [ "$(yq -r '."proj-a".devcontainer' "$registry")" = "/tmp/proj-a.json" ]
  [ "$(yq -r '."proj-b".devcontainer' "$registry")" = "/tmp/proj-b.json" ]
  [ "$(yq -r '."proj-b" | has("dockerfile")' "$registry")" = "false" ]
  [ "$(yq -r '."proj-b" | has("image")' "$registry")" = "false" ]
  [ "$(yq -r '."proj-b" | has("sibling_discovery")' "$registry")" = "false" ]
}

@test "register_project_defaults writes minimum-viable entry" {
  local registry="${XDG_CONFIG_HOME}/dctl/projects.yaml"

  run register_project_defaults "proj-a" "/tmp/proj-a.json"
  [ "$status" -eq 0 ]
  [ "$(yq -r '."proj-a".devcontainer' "$registry")" = "/tmp/proj-a.json" ]
  [ "$(yq -r '."proj-a" | has("dockerfile")' "$registry")" = "false" ]
  [ "$(yq -r '."proj-a" | has("image")' "$registry")" = "false" ]
  [ "$(yq -r '."proj-a" | has("sibling_discovery")' "$registry")" = "false" ]
}

@test "register_project_defaults fails on invalid existing registry" {
  printf 'not: valid: yaml: [broken\n' >"${XDG_CONFIG_HOME}/dctl/projects.yaml"

  run register_project_defaults "proj-a" "/tmp/proj-a.json"
  [ "$status" -ne 0 ]
  [[ $output == *"Invalid YAML"* || $output == *"ailed"* ]]
}

@test "register_project_defaults creates config directory when missing" {
  rm -rf "${XDG_CONFIG_HOME}/dctl"
  [ ! -d "${XDG_CONFIG_HOME}/dctl" ]

  run register_project_defaults "proj-a" "/tmp/proj-a.json"
  [ "$status" -eq 0 ]
  [ -d "${XDG_CONFIG_HOME}/dctl" ]
  [ -f "${XDG_CONFIG_HOME}/dctl/projects.yaml" ]
  [ "$(yq -r '."proj-a".devcontainer' "${XDG_CONFIG_HOME}/dctl/projects.yaml")" = "/tmp/proj-a.json" ]
}
