#!/usr/bin/env bats

# bats file_tags=unit

load test_helper

setup() {
  setup_test_fixtures
  repo_root="${BATS_TEST_DIRNAME}/.."
  paths_sh="${repo_root}/lib/dctl/_lib/paths.sh"
}

teardown() {
  teardown_test_fixtures
}

# Source paths.sh in a clean subshell with a controlled env, then print
# the resolved value of $1. Strips inherited DCTL_*/XDG_* by default;
# additional args after $1 are exported into the subshell.
resolve_var() {
  local var="$1"
  shift
  # shellcheck disable=SC2016
  env -i HOME="$HOME" PATH="$PATH" "$@" \
    bash -c 'set -u; source "'"$paths_sh"'"; printf "%s\n" "${'"$var"'}"'
}

@test "defaults: DCTL_CONFIG_DIR resolves under XDG_CONFIG_HOME" {
  run resolve_var DCTL_CONFIG_DIR XDG_CONFIG_HOME="${TEST_TMPDIR}/xc"
  [ "$status" -eq 0 ]
  [ "$output" = "${TEST_TMPDIR}/xc/dctl" ]
}

@test "defaults: IMAGES_DIR and DCTL_SCHEMAS_DIR resolve under XDG_DATA_HOME" {
  run resolve_var IMAGES_DIR XDG_DATA_HOME="${TEST_TMPDIR}/xd"
  [ "$status" -eq 0 ]
  [ "$output" = "${TEST_TMPDIR}/xd/dctl/images" ]

  run resolve_var DCTL_SCHEMAS_DIR XDG_DATA_HOME="${TEST_TMPDIR}/xd"
  [ "$status" -eq 0 ]
  [ "$output" = "${TEST_TMPDIR}/xd/dctl/schemas" ]
}

@test "DCTL_HOME redirects config, cache, and data roots" {
  # DCTL_DATA_DIR set explicitly to bypass the repo auto-detect (covered
  # in its own test); this verifies the explicit redirect contract.
  local h="${TEST_TMPDIR}/h"
  local d="${h}/share"
  local args=(DCTL_HOME="$h" DCTL_DATA_DIR="$d")

  run resolve_var DCTL_CONFIG_DIR "${args[@]}"
  [ "$output" = "${h}/config" ]

  run resolve_var DCTL_CACHE_DIR "${args[@]}"
  [ "$output" = "${h}/cache" ]

  run resolve_var DCTL_DATA_DIR "${args[@]}"
  [ "$output" = "$d" ]

  run resolve_var IMAGES_DIR "${args[@]}"
  [ "$output" = "${d}/images" ]

  run resolve_var DEVCONTAINERS_DIR "${args[@]}"
  [ "$output" = "${d}/devcontainers" ]

  run resolve_var DCTL_SCHEMAS_DIR "${args[@]}"
  [ "$output" = "${d}/schemas" ]

  run resolve_var DCTL_DEVCONTAINER_DIR "${args[@]}"
  [ "$output" = "${h}/config/devcontainer" ]
}

@test "individual DCTL_CONFIG_DIR override wins over DCTL_HOME" {
  local h="${TEST_TMPDIR}/h"
  local c="${TEST_TMPDIR}/explicit-config"
  local d="${h}/share"

  run resolve_var DCTL_CONFIG_DIR DCTL_HOME="$h" DCTL_CONFIG_DIR="$c" DCTL_DATA_DIR="$d"
  [ "$output" = "$c" ]

  # cache and data still derive from DCTL_HOME (data explicit to skip auto-detect)
  run resolve_var DCTL_CACHE_DIR DCTL_HOME="$h" DCTL_CONFIG_DIR="$c" DCTL_DATA_DIR="$d"
  [ "$output" = "${h}/cache" ]

  run resolve_var DCTL_DATA_DIR DCTL_HOME="$h" DCTL_CONFIG_DIR="$c" DCTL_DATA_DIR="$d"
  [ "$output" = "$d" ]
}

@test "DCTL_HOME auto-detects repo root as DCTL_DATA_DIR when lib parent has seed dirs" {
  local h="${TEST_TMPDIR}/h"
  local repo="${TEST_TMPDIR}/repo"
  mkdir -p "${repo}/lib/dctl/_lib" \
    "${repo}/images" "${repo}/devcontainers" "${repo}/schemas"
  cp "$paths_sh" "${repo}/lib/dctl/_lib/paths.sh"

  # shellcheck disable=SC2016
  run env -i HOME="$HOME" PATH="$PATH" DCTL_HOME="$h" \
    bash -c 'source "'"$repo"'/lib/dctl/_lib/paths.sh"; printf "%s\n" "$DCTL_DATA_DIR"'
  [ "$status" -eq 0 ]
  [ "$output" = "$repo" ]
}

@test 'DCTL_HOME falls back to $DCTL_HOME/share when lib parent lacks seed dirs' {
  local h="${TEST_TMPDIR}/h"
  local nonrepo="${TEST_TMPDIR}/installed"
  mkdir -p "${nonrepo}/lib/dctl/_lib"
  cp "$paths_sh" "${nonrepo}/lib/dctl/_lib/paths.sh"

  # shellcheck disable=SC2016
  run env -i HOME="$HOME" PATH="$PATH" DCTL_HOME="$h" \
    bash -c 'source "'"$nonrepo"'/lib/dctl/_lib/paths.sh"; printf "%s\n" "$DCTL_DATA_DIR"'
  [ "$status" -eq 0 ]
  [ "$output" = "${h}/share" ]
}

@test "DCTL_DATA_DIR alone redirects seed roots without DCTL_HOME" {
  local d="${TEST_TMPDIR}/repo"

  run resolve_var IMAGES_DIR DCTL_DATA_DIR="$d"
  [ "$output" = "${d}/images" ]

  run resolve_var DEVCONTAINERS_DIR DCTL_DATA_DIR="$d"
  [ "$output" = "${d}/devcontainers" ]

  run resolve_var DCTL_SCHEMAS_DIR DCTL_DATA_DIR="$d"
  [ "$output" = "${d}/schemas" ]
}
