#!/usr/bin/env bats

# bats file_tags=unit

# The doc examples in docs/examples/ are a working dctl configuration. dctl
# reads them here only because DCTL_CONFIG_DIR points at them; no command and
# no install step uses them otherwise.

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  setup_test_fixtures
  local repo_root
  repo_root="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  export EXAMPLES_DIR="${repo_root}/docs/examples/config/dctl"
  export DCTL_CONFIG_DIR="$EXAMPLES_DIR"
  export DCTL_SCHEMAS_DIR="${repo_root}/schemas"
  export XDG_RUNTIME_DIR="${TEST_TMPDIR}/xdg-runtime"
  export WORKSPACE_FOLDER="${TEST_TMPDIR}/workspace"
  mkdir -p "$XDG_RUNTIME_DIR" "$WORKSPACE_FOLDER"
  unset DCTL_CONFIG DCTL_CLI_CONFIG 2>/dev/null || true
  DCTL_LIB_DIR="${repo_root}/lib/dctl"
  set -euo pipefail
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/common.sh"
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/image.sh"
  # shellcheck source=/dev/null
  source "${DCTL_LIB_DIR}/config.sh"
}

teardown() {
  teardown_test_fixtures
}

@test "the example manifest validates against the compose schema" {
  run _validate_compose_manifest "${EXAMPLES_DIR}/devcontainer/example.yaml"
  [ "$status" -eq 0 ]
  if command -v check-jsonschema >/dev/null 2>&1; then
    run check-jsonschema --force-filetype yaml \
      --schemafile "${DCTL_SCHEMAS_DIR}/compose.schema.yaml" \
      "${EXAMPLES_DIR}/devcontainer/example.yaml"
    [ "$status" -eq 0 ]
  fi
}

@test "the example registry validates against the projects schema" {
  run _validate_registry "${EXAMPLES_DIR}/projects.yaml"
  [ "$status" -eq 0 ]
  if command -v check-jsonschema >/dev/null 2>&1; then
    run check-jsonschema --force-filetype yaml \
      --schemafile "${DCTL_SCHEMAS_DIR}/projects.schema.yaml" \
      "${EXAMPLES_DIR}/projects.yaml"
    [ "$status" -eq 0 ]
  fi
}

@test "the example manifest composes into one devcontainer.json" {
  run generate_devcontainer example
  [ "$status" -eq 0 ]
  local generated
  generated="$(devcontainer_generated_path_for_manifest example)"
  [ "${lines[-1]}" = "$generated" ]
  [ -f "$generated" ]
  [ "$(jq -r '.image' "$generated")" = "devimg/example:latest" ]
  # shellcheck disable=SC2016 # ${localEnv:...} is a devcontainer.json variable; must NOT be shell-expanded
  [ "$(jq -r '.remoteUser' "$generated")" = '${localEnv:USER}' ]
  # shellcheck disable=SC2016 # as above
  [ "$(jq -r '.runArgs[1]' "$generated")" = 'seccomp=${localEnv:HOME}/.config/dctl/devcontainer/agents/seccomp-bwrap.json' ]
  # The leaf runs no lifecycle command, and the optional dotfiles layer is not
  # in the manifest, so nothing needs DOTFILES.
  [ "$(jq -c '.postCreateCommand // {}' "$generated")" = "{}" ]
  [ "$(jq '[.mounts[].source | select(test("DOTFILES"))] | length' "$generated")" = "0" ]
}

@test "the example seccomp profile is valid JSON and default-allow" {
  run jq -r '.defaultAction' "${EXAMPLES_DIR}/devcontainer/agents/seccomp-bwrap.json"
  [ "$status" -eq 0 ]
  [ "$output" = "SCMP_ACT_ALLOW" ]
}

@test "the example image is a user image that dctl image build finds" {
  # DCTL_IMAGES_DIR follows DCTL_CONFIG_DIR, so it is the images/ of the examples.
  [ "$DCTL_IMAGES_DIR" = "${EXAMPLES_DIR}/images" ]
  run discover_image_targets
  [ "$status" -eq 0 ]
  [ "$output" = "example" ]
}
