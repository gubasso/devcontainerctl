#!/usr/bin/env bats

# bats file_tags=unit

load test_helper

setup() {
  setup_test_fixtures
  export XDG_DATA_HOME="${TEST_TMPDIR}/xdg-data"
  export XDG_CONFIG_HOME="${TEST_TMPDIR}/xdg-config"
  export XDG_CACHE_HOME="${TEST_TMPDIR}/xdg-cache"
  # The merged config is regenerated (never cached) under $XDG_RUNTIME_DIR.
  export XDG_RUNTIME_DIR="${TEST_TMPDIR}/xdg-runtime"
  export WORKSPACE_FOLDER="${TEST_TMPDIR}/workspace"
  mkdir -p "${XDG_DATA_HOME}/dctl/images" "${XDG_DATA_HOME}/dctl/schemas" \
    "${XDG_CONFIG_HOME}/dctl" "${XDG_RUNTIME_DIR}/dctl" "$WORKSPACE_FOLDER"
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

@test "registry lookup returns manifest name for known project" {
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<YAML
test-project:
  devcontainer-manifest: general
YAML

  run _registry_lookup_devcontainer_manifest "test-project"
  [ "$status" -eq 0 ]
  [ "$output" = "general" ]
}

@test "registry lookup returns empty for unknown project" {
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<YAML
other-project:
  devcontainer-manifest: general
YAML

  run _registry_lookup_devcontainer_manifest "unknown-project"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "registry lookup returns empty when file does not exist" {
  run _registry_lookup_devcontainer_manifest "any-project"
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

  run _registry_lookup_devcontainer_manifest "proj"
  [ "$status" -ne 0 ]
  [[ $output == *"Unrecognized key"* || $output == *"additional properties"* || $output == *"ailed"* ]]
}

@test "registry validation rejects image key" {
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<'YAML'
proj:
  image: devimg/foo:latest
YAML

  run _registry_lookup_devcontainer_manifest "proj"
  [ "$status" -ne 0 ]
  [[ $output == *"Unrecognized key"* || $output == *"additional properties"* || $output == *"ailed"* ]]
}

@test "registry validation rejects legacy devcontainer key" {
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<'YAML'
proj:
  devcontainer: /tmp/legacy.json
YAML

  run _registry_lookup_devcontainer_manifest "proj"
  [ "$status" -ne 0 ]
  [[ $output == *"Unrecognized key"* || $output == *"additional properties"* || $output == *"ailed"* ]]
}

# --- Schema validation ---

@test "registry validation accepts valid file" {
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<YAML
my-repo:
  devcontainer-manifest: general
YAML

  run _validate_registry "${XDG_CONFIG_HOME}/dctl/projects.yaml"
  [ "$status" -eq 0 ]
}

@test "registry validation accepts explicit sibling_discovery false" {
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<YAML
my-repo:
  devcontainer-manifest: general
  sibling_discovery: false
YAML

  run _validate_registry "${XDG_CONFIG_HOME}/dctl/projects.yaml"
  [ "$status" -eq 0 ]
}

@test "registry validation accepts a valid registry at a path without a .yaml extension" {
  # check-jsonschema picks its parser from the instance's extension, so a
  # candidate path like projects.yaml.tmp.<pid> was parsed as JSON and died with
  # a JSONDecodeError, breaking every `dctl init`. Content, not name, decides.
  local candidate="${XDG_CONFIG_HOME}/dctl/projects.yaml.tmp.4242"
  cat >"$candidate" <<YAML
my-repo:
  devcontainer-manifest: general
YAML

  run _validate_registry "$candidate"
  [ "$status" -eq 0 ]
}

@test "registry validation still rejects an invalid registry at a path without a .yaml extension" {
  local candidate="${XDG_CONFIG_HOME}/dctl/projects.yaml.tmp.4243"
  cat >"$candidate" <<YAML
my-repo:
  unknown_key: value
YAML

  run _validate_registry "$candidate"
  [ "$status" -ne 0 ]
}

@test "register_project_defaults writes the registry when the schema is deployed" {
  # End-to-end guard for the same bug: register_project_defaults validates a
  # temp candidate before swapping it in, so a parser mismatch there fails
  # every init even though the resulting registry is valid.
  run register_project_defaults "my-repo" "general"
  [ "$status" -eq 0 ]

  run yq -r '.["my-repo"]["devcontainer-manifest"]' "${XDG_CONFIG_HOME}/dctl/projects.yaml"
  [ "$status" -eq 0 ]
  [ "$output" = "general" ]
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

@test "registry validation rejects non-string devcontainer-manifest" {
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<YAML
my-repo:
  devcontainer-manifest: 42
YAML

  run _validate_registry "${XDG_CONFIG_HOME}/dctl/projects.yaml"
  [ "$status" -ne 0 ]
  [[ $output == *"devcontainer-manifest"* ]]
}

@test "registry validation rejects devcontainer-manifest with disallowed characters" {
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<YAML
my-repo:
  devcontainer-manifest: ../escape
YAML

  run _validate_registry "${XDG_CONFIG_HOME}/dctl/projects.yaml"
  [ "$status" -ne 0 ]
  # check-jsonschema reports a pattern failure; yq fallback names the project
  [[ $output == *"my-repo"* || $output == *"pattern"* || $output == *"ailed"* ]]
}

@test "registry validation rejects devcontainer-manifest with slash" {
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<YAML
my-repo:
  devcontainer-manifest: foo/bar
YAML

  run _validate_registry "${XDG_CONFIG_HOME}/dctl/projects.yaml"
  [ "$status" -ne 0 ]
  [[ $output == *"my-repo"* || $output == *"pattern"* || $output == *"ailed"* ]]
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

@test "registry manifest overrides local config" {
  # Local config exists
  mkdir -p "$(workspace_devcontainer_dir)"
  printf '{"image": "local"}\n' >"$(workspace_devcontainer_file)"

  # Deploy a manifest + layers so resolution can merge the registered config
  # fresh (there is no cache to pre-seed).
  mkdir -p "${XDG_CONFIG_HOME}/dctl/devcontainer/base" \
    "${XDG_CONFIG_HOME}/dctl/devcontainer/general"
  printf '{"image": "base"}\n' >"${XDG_CONFIG_HOME}/dctl/devcontainer/base/devcontainer.json"
  printf '{"image": "registry"}\n' >"${XDG_CONFIG_HOME}/dctl/devcontainer/general/devcontainer.json"
  cat >"${XDG_CONFIG_HOME}/dctl/devcontainer/general.yaml" <<'YAML'
layers:
  - base
  - general
YAML

  # Need canonical name for the current workspace
  local canonical
  canonical="$(resolve_canonical_project_name)"
  cat >"${XDG_CONFIG_HOME}/dctl/projects.yaml" <<YAML
${canonical}:
  devcontainer-manifest: general
YAML

  local gen
  gen="$(devcontainer_generated_path_for_manifest general)"

  run resolve_devcontainer_config
  [ "$status" -eq 0 ]
  # Resolution returns the freshly-merged registry config, not the local file.
  [[ $output == *"$gen"* ]]
  [ "$(jq -r '.image' "$gen")" = "registry" ]
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

  run register_project_defaults "proj-a" "general"
  [ "$status" -eq 0 ]
  [ -f "$registry" ]
  [ "$(yq -r '.["proj-a"]["devcontainer-manifest"]' "$registry")" = "general" ]
  [ "$(yq -r '."proj-a" | has("dockerfile")' "$registry")" = "false" ]
  [ "$(yq -r '."proj-a" | has("image")' "$registry")" = "false" ]
  [ "$(yq -r '."proj-a" | has("sibling_discovery")' "$registry")" = "false" ]
}

@test "register_project_defaults updates existing project and preserves sibling_discovery" {
  local registry="${XDG_CONFIG_HOME}/dctl/projects.yaml"
  cat >"$registry" <<'YAML'
proj-a:
  devcontainer-manifest: general
  sibling_discovery: false
YAML

  run register_project_defaults "proj-a" "python"
  [ "$status" -eq 0 ]
  [ "$(yq -r '.["proj-a"]["devcontainer-manifest"]' "$registry")" = "python" ]
  [ "$(yq -r '."proj-a" | has("dockerfile")' "$registry")" = "false" ]
  [ "$(yq -r '."proj-a" | has("image")' "$registry")" = "false" ]
  [ "$(yq -r '."proj-a".sibling_discovery' "$registry")" = "false" ]
}

@test "register_project_defaults strips default sibling_discovery on re-register" {
  local registry="${XDG_CONFIG_HOME}/dctl/projects.yaml"
  cat >"$registry" <<'YAML'
proj-a:
  devcontainer-manifest: general
  sibling_discovery: true
YAML

  run register_project_defaults "proj-a" "python"
  [ "$status" -eq 0 ]
  [ "$(yq -r '.["proj-a"]["devcontainer-manifest"]' "$registry")" = "python" ]
  [ "$(yq -r '."proj-a" | has("dockerfile")' "$registry")" = "false" ]
  [ "$(yq -r '."proj-a" | has("image")' "$registry")" = "false" ]
  [ "$(yq -r '."proj-a" | has("sibling_discovery")' "$registry")" = "false" ]
}

@test "register_project_defaults appends to existing registry" {
  local registry="${XDG_CONFIG_HOME}/dctl/projects.yaml"
  cat >"$registry" <<'YAML'
proj-a:
  devcontainer-manifest: general
YAML

  run register_project_defaults "proj-b" "python"
  [ "$status" -eq 0 ]
  [ "$(yq -r '.["proj-a"]["devcontainer-manifest"]' "$registry")" = "general" ]
  [ "$(yq -r '.["proj-b"]["devcontainer-manifest"]' "$registry")" = "python" ]
  [ "$(yq -r '."proj-b" | has("dockerfile")' "$registry")" = "false" ]
  [ "$(yq -r '."proj-b" | has("image")' "$registry")" = "false" ]
  [ "$(yq -r '."proj-b" | has("sibling_discovery")' "$registry")" = "false" ]
}

@test "register_project_defaults writes minimum-viable entry" {
  local registry="${XDG_CONFIG_HOME}/dctl/projects.yaml"

  run register_project_defaults "proj-a" "general"
  [ "$status" -eq 0 ]
  [ "$(yq -r '.["proj-a"]["devcontainer-manifest"]' "$registry")" = "general" ]
  [ "$(yq -r '."proj-a" | has("dockerfile")' "$registry")" = "false" ]
  [ "$(yq -r '."proj-a" | has("image")' "$registry")" = "false" ]
  [ "$(yq -r '."proj-a" | has("sibling_discovery")' "$registry")" = "false" ]
}

@test "register_project_defaults fails on invalid existing registry" {
  printf 'not: valid: yaml: [broken\n' >"${XDG_CONFIG_HOME}/dctl/projects.yaml"

  run register_project_defaults "proj-a" "general"
  [ "$status" -ne 0 ]
  [[ $output == *"Invalid YAML"* || $output == *"ailed"* ]]
}

@test "register_project_defaults creates config directory when missing" {
  rm -rf "${XDG_CONFIG_HOME}/dctl"
  [ ! -d "${XDG_CONFIG_HOME}/dctl" ]

  run register_project_defaults "proj-a" "general"
  [ "$status" -eq 0 ]
  [ -d "${XDG_CONFIG_HOME}/dctl" ]
  [ -f "${XDG_CONFIG_HOME}/dctl/projects.yaml" ]
  [ "$(yq -r '.["proj-a"]["devcontainer-manifest"]' "${XDG_CONFIG_HOME}/dctl/projects.yaml")" = "general" ]
}

@test "register_project_defaults scrubs legacy devcontainer key" {
  local registry="${XDG_CONFIG_HOME}/dctl/projects.yaml"
  cat >"$registry" <<'YAML'
proj-a:
  devcontainer: $HOME/cache/path/devcontainer.json
  sibling_discovery: false
YAML

  run register_project_defaults "proj-a" "general"
  [ "$status" -eq 0 ]
  [ "$(yq -r '.["proj-a"]["devcontainer-manifest"]' "$registry")" = "general" ]
  [ "$(yq -r '.["proj-a"] | has("devcontainer")' "$registry")" = "false" ]
}
