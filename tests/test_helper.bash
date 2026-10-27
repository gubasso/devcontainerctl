setup_test_fixtures() {
  # `git commit` exports GIT_DIR and friends to its hooks, and the bats-unit
  # hook inherits them. An absolute GIT_DIR makes `git -C <fixture>` read this
  # repository instead of the fixture, so resolve_canonical_project_name
  # returns the real project name and the provider and forge-auth cases fail
  # for the wrong reason. The suite owns its own git environment.
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX

  TEST_TMPDIR="$(mktemp -d "${BATS_TEST_TMPDIR}/dctl.XXXXXX")"
  export TEST_TMPDIR
  mkdir -p "${TEST_TMPDIR}/bin"
  : >"${TEST_TMPDIR}/mock_calls.log"
}

teardown_test_fixtures() {
  rm -rf "$TEST_TMPDIR"
}

enable_mocks() {
  export PATH="${TEST_TMPDIR}/bin:${PATH}"
}

create_mock() {
  local name="$1"
  local exit_code="$2"
  local stdout="${3:-}"

  cat >"${TEST_TMPDIR}/bin/${name}" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$(basename "\$0") \$*" >>"${TEST_TMPDIR}/mock_calls.log"
if [[ -n "$stdout" ]]; then
  printf '%s\n' "$stdout"
fi
exit $exit_code
EOF
  chmod +x "${TEST_TMPDIR}/bin/${name}"
}

# A devcontainer mock that runs the in-container shell on the host. It drops
# the `exec` options up to the word `bash`, then hands the command string to a
# plain `bash -c`, with no rc file and no profile. A test then sees the exact
# argument words that the container shell would give the command, which the
# call log of create_mock cannot show.
create_devcontainer_shell_mock() {
  cat >"${TEST_TMPDIR}/bin/devcontainer" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 && $1 != bash ]]; do shift; done
[[ $# -eq 3 ]] || {
  printf 'devcontainer mock: expected bash FLAGS STRING, got %d words\n' "$#" >&2
  exit 97
}
exec bash --norc --noprofile -c "$3"
EOF
  chmod +x "${TEST_TMPDIR}/bin/devcontainer"
}

sanitized_bin_excluding() {
  local sanitized="${TEST_TMPDIR}/sanitized_bin"
  mkdir -p "$sanitized"
  # Mirror every directory on PATH, not just /usr/bin and /bin: on a
  # store-based distribution (Nix, Guix) the core tools live outside the FHS
  # paths, so a hardcoded list produces a bin/ without realpath or grep and the
  # command under test fails for the wrong reason. Skip the mock directory so
  # that a mock never leaks into the sanitized set.
  local dir src dst
  while IFS= read -r dir; do
    [[ -n $dir && -d $dir ]] || continue
    [[ $dir == "${TEST_TMPDIR}/bin" ]] && continue
    for src in "$dir"/*; do
      [[ -e $src ]] || continue
      dst="${sanitized}/$(basename "$src")"
      [[ -e $dst ]] && continue
      ln -s "$src" "$dst" 2>/dev/null || true
    done
  done < <(printf '%s\n' "${PATH//:/$'\n'}")
  local name
  for name in "$@"; do
    rm -f "${sanitized}/${name}"
  done
  printf '%s\n' "$sanitized"
}

assert_mock_called() {
  local pattern="$1"
  grep -F -- "$pattern" "${TEST_TMPDIR}/mock_calls.log" >/dev/null
}

assert_mock_not_called() {
  local pattern="$1"
  if grep -F -- "$pattern" "${TEST_TMPDIR}/mock_calls.log" >/dev/null; then
    echo "Unexpected mock call matching: $pattern" >&2
    return 1
  fi
}
