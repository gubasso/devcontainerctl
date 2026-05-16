#!/usr/bin/env bats

# bats file_tags=unit

load test_helper

setup() {
  setup_test_fixtures
  repo_root="${BATS_TEST_DIRNAME}/.."
}

teardown() {
  teardown_test_fixtures
}

@test "every command verb file defines exactly one cmd_<group>_<verb>" {
  for f in "$repo_root"/lib/dctl/commands/*/*.sh; do
    local base
    base="$(basename "$f")"
    [[ $base == _dispatch.sh ]] && continue
    [[ $base == _* ]] && continue
    local group
    group="$(basename "$(dirname "$f")")"
    local verb="${base%.sh}"
    local expected="cmd_${group}_${verb}"
    local count
    count="$(grep -Ec "^${expected}\(\) \{$" "$f")"
    [ "$count" -eq 1 ] || {
      echo "expected one $expected() in $f (got $count)"
      return 1
    }
    local total
    total="$(grep -Ec '^cmd_[A-Za-z0-9_]+\(\) \{$' "$f")"
    [ "$total" -eq 1 ] || {
      echo "$f defines multiple cmd_ functions"
      return 1
    }
  done
}

@test "_lib files define at most one function (15a exemptions allowed)" {
  local exempt=("_lib/source.sh" "_lib/log.sh" "_lib/paths.sh")
  while IFS= read -r -d '' f; do
    local rel="${f#"${repo_root}"/lib/dctl/}"
    local skip=false
    for e in "${exempt[@]}"; do
      [[ $rel == "$e" ]] && skip=true
    done
    "$skip" && continue
    local n
    n="$(grep -Ec '^[A-Za-z0-9_]+\(\) \{$' "$f")"
    [ "$n" -le 1 ] || {
      echo "$rel has $n functions (limit 1)"
      return 1
    }
  done < <(find "${repo_root}/lib/dctl/_lib" -type f -name '*.sh' -print0)
}

@test "no lib/dctl file exceeds 500 lines" {
  run bash -c "find '${repo_root}/lib/dctl' -type f -name '*.sh' -print0 | xargs -0 wc -l | awk '\$2!=\"total\" && \$1>500 {print; bad=1} END {exit bad}'"
  [ "$status" -eq 0 ] || {
    echo "$output"
    return 1
  }
}

@test "bin/dctl sources only _lib/source.sh, log.sh, paths.sh at startup" {
  run grep -nE '^(source |__dctl_require )' "${repo_root}/bin/dctl"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [[ ${lines[0]} == *"_lib/source.sh"* ]]
  [[ ${lines[1]} == *"_lib/log.sh"* ]]
  [[ ${lines[2]} == *"_lib/paths.sh"* ]]
}
