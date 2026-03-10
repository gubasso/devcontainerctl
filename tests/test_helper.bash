setup_test_fixtures() {
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
