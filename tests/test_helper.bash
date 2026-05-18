# Test helper conventions:
# - PATH-shim mocks live under ${TEST_TMPDIR}/bin and must be prepended ahead of
#   any test-local PATH changes so adapter/runtime tests pick up the shimmed
#   binaries before the host tools.
# - Runtime adapter tests can skip the expensive krun doctor path by exporting
#   _DCTL_KRUN_PREFLIGHT_OK=1; tests that exercise preflight behavior must unset
#   it explicitly first.

setup_test_fixtures() {
  TEST_TMPDIR="$(mktemp -d "${BATS_TEST_TMPDIR}/dctl.XXXXXX")"
  export TEST_TMPDIR
  mkdir -p "${TEST_TMPDIR}/bin"
  mkdir -p "${TEST_TMPDIR}/argv"
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

record_argv_mock() {
  local name="$1"
  local exit_code="${2:-0}"
  local stdout="${3:-}"

  cat >"${TEST_TMPDIR}/bin/${name}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
argv_dir="${TEST_TMPDIR}/argv"
mkdir -p "\$argv_dir"
count_file="\${argv_dir}/$(printf '%s' "$name").calls"
count=0
if [[ -f "\$count_file" ]]; then
  count="\$(cat "\$count_file")"
fi
count=\$((count + 1))
printf '%s' "\$count" >"\$count_file"
argv_file="\${argv_dir}/$(printf '%s' "$name").\${count}.argv"
printf '%s\n' "\$(basename "\$0") \$*" >>"${TEST_TMPDIR}/mock_calls.log"
for arg in "\$@"; do
  printf '%s\0' "\$arg" >>"\$argv_file"
done
if [[ -n "$stdout" ]]; then
  printf '%s\n' "$stdout"
fi
exit $exit_code
EOF
  chmod +x "${TEST_TMPDIR}/bin/${name}"
}

sanitized_bin_excluding() {
  local sanitized="${TEST_TMPDIR}/sanitized_bin"
  mkdir -p "$sanitized"
  local src dst
  for src in /usr/bin/* /bin/*; do
    [[ -e $src ]] || continue
    dst="${sanitized}/$(basename "$src")"
    [[ -e $dst ]] && continue
    ln -s "$src" "$dst" 2>/dev/null || true
  done
  local name
  for name in "$@"; do
    rm -f "${sanitized}/${name}"
  done
  printf '%s\n' "$sanitized"
}

assert_argv_call() {
  local name="$1"
  local call_index="$2"
  shift 2

  local argv_file="${TEST_TMPDIR}/argv/${name}.${call_index}.argv"
  [[ -f $argv_file ]] || {
    echo "Missing argv capture: ${argv_file}" >&2
    return 1
  }

  local -a actual expected
  mapfile -d '' -t actual <"$argv_file"
  expected=("$@")

  if [[ ${#actual[@]} -ne ${#expected[@]} ]]; then
    echo "argv length mismatch for ${name} call ${call_index}: expected ${#expected[@]}, got ${#actual[@]}" >&2
  else
    local i
    for i in "${!expected[@]}"; do
      [[ ${actual[$i]} == "${expected[$i]}" ]] || {
        echo "argv mismatch for ${name} call ${call_index} at index ${i}: expected '${expected[$i]}', got '${actual[$i]}'" >&2
        _print_argv_debug "expected" "${expected[@]}"
        _print_argv_debug "actual" "${actual[@]}"
        return 1
      }
    done
    return 0
  fi

  _print_argv_debug "expected" "${expected[@]}"
  _print_argv_debug "actual" "${actual[@]}"
  return 1
}

assert_argv_contains_sequence() {
  local name="$1"
  local call_index="$2"
  shift 2

  local argv_file="${TEST_TMPDIR}/argv/${name}.${call_index}.argv"
  [[ -f $argv_file ]] || {
    echo "Missing argv capture: ${argv_file}" >&2
    return 1
  }

  local -a actual seq
  mapfile -d '' -t actual <"$argv_file"
  seq=("$@")

  local actual_len="${#actual[@]}"
  local seq_len="${#seq[@]}"
  local i j found
  for ((i = 0; i + seq_len <= actual_len; i++)); do
    found=1
    for ((j = 0; j < seq_len; j++)); do
      if [[ ${actual[$((i + j))]} != "${seq[$j]}" ]]; then
        found=0
        break
      fi
    done
    if [[ $found -eq 1 ]]; then
      return 0
    fi
  done

  echo "Did not find contiguous argv sequence for ${name} call ${call_index}" >&2
  _print_argv_debug "wanted" "${seq[@]}"
  _print_argv_debug "actual" "${actual[@]}"
  return 1
}

creds_fixture_home() {
  local home_dir="${TEST_TMPDIR}/home"
  export HOME="$home_dir"
  mkdir -p \
    "$HOME/.config/gh" \
    "$HOME/.local/state/glab-cli" \
    "$HOME/.claude" \
    "$HOME/.codex" \
    "$HOME/.gemini"
  printf '%s\n' "$HOME"
}

_print_argv_debug() {
  local label="$1"
  shift

  local -a argv
  argv=("$@")

  printf '%s:\n' "$label" >&2
  local i
  for i in "${!argv[@]}"; do
    printf '  [%s] %q\n' "$i" "${argv[$i]}" >&2
  done
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
