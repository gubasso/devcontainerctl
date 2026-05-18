#!/usr/bin/env bats

# bats file_tags=e2e

setup_file() {
  if ! command -v podman >/dev/null 2>&1; then
    skip "E2E tests require podman"
  fi
  if [ ! -e /dev/kvm ] || [ ! -r /dev/kvm ]; then
    skip "E2E tests require a readable /dev/kvm"
  fi
}

setup() {
  export TEST_TMPDIR
  TEST_TMPDIR="$(mktemp -d "${BATS_TEST_TMPDIR}/dctl.e2e.XXXXXX")"
  export XDG_DATA_HOME="${TEST_TMPDIR}/xdg-data"
  export XDG_CONFIG_HOME="${TEST_TMPDIR}/xdg-config"
  export XDG_CACHE_HOME="${TEST_TMPDIR}/xdg-cache"
  export HOME="${TEST_TMPDIR}/home"
  export WORKSPACE_FOLDER="${TEST_TMPDIR}/workspace"
  mkdir -p "${XDG_DATA_HOME}/dctl" "${XDG_CONFIG_HOME}/dctl" "${XDG_CACHE_HOME}/dctl" "$HOME" "${WORKSPACE_FOLDER}/.devcontainer"
  cat >"${WORKSPACE_FOLDER}/.devcontainer/devcontainer.json" <<'EOF'
{
  "image": "quay.io/libpod/busybox:latest"
}
EOF

  if ! podman image inspect quay.io/libpod/busybox:latest >/dev/null 2>&1; then
    podman pull quay.io/libpod/busybox:latest >/dev/null 2>&1 || skip "E2E smoke requires quay.io/libpod/busybox:latest locally or pullable"
  fi
}

teardown() {
  (
    cd "$WORKSPACE_FOLDER" || exit 0
    bash "${BATS_TEST_DIRNAME}/../bin/dctl" ws down >/dev/null 2>&1 || true
  )
  rm -rf "$TEST_TMPDIR"
}

@test "dctl ws up uses krun runtime and supports exec plus teardown" {
  run bash -lc 'cd "$WORKSPACE_FOLDER" && bash "'"$BATS_TEST_DIRNAME"'/../bin/dctl" ws up'
  [ "$status" -eq 0 ]

  local ctr
  ctr="$(podman ps --filter "label=devcontainer.local_folder=${WORKSPACE_FOLDER}" --format '{{.ID}}' | head -n1)"
  [ "$ctr" != "" ]

  run podman inspect "$ctr" --format '{{.OCIRuntime}}'
  [ "$status" -eq 0 ]
  [ "$output" = "krun" ]

  run bash -lc 'cd "$WORKSPACE_FOLDER" && bash "'"$BATS_TEST_DIRNAME"'/../bin/dctl" ws exec -- true'
  [ "$status" -eq 0 ]

  run bash -lc 'cd "$WORKSPACE_FOLDER" && bash "'"$BATS_TEST_DIRNAME"'/../bin/dctl" ws down'
  [ "$status" -eq 0 ]

  run podman ps -a --filter "label=devcontainer.local_folder=${WORKSPACE_FOLDER}" --format '{{.ID}}'
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
