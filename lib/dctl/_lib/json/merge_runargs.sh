# shellcheck shell=bash

[[ -n ${_DCTL_LIB_JSON_MERGE_RUNARGS_LOADED:-} ]] && return 0
readonly _DCTL_LIB_JSON_MERGE_RUNARGS_LOADED=1

_merge_runargs_json() {
  local base_json="$1"
  local tmpl_json="$2"
  local -a items ordered_ids
  local -A keyed_flags seen_ids id_flag id_value
  local idx flag value identity

  # Quote the keys so shfmt does not insert spaces around the dashes inside
  # the bracket subscripts (which produces literal "--cgroup - parent" keys).
  keyed_flags=(
    ["--name"]=1
    ["--hostname"]=1
    ["--label"]=1
    ["--user"]=1
    ["--workdir"]=1
    ["--network"]=1
    ["--ipc"]=1
    ["--pid"]=1
    ["--uts"]=1
    ["--cgroup-parent"]=1
    ["--memory"]=1
    ["--cpus"]=1
    ["--cpuset-cpus"]=1
    ["--cpuset-mems"]=1
  )

  mapfile -t items < <(
    jq -sr '((.[0].runArgs // []) + (.[1].runArgs // []))[]' \
      <(printf '%s\n' "$base_json") \
      <(printf '%s\n' "$tmpl_json")
  )

  if ((${#items[@]} % 2 != 0)); then
    printf 'runArgs must contain flag/value pairs; got odd-length array (%d entries)\n' "${#items[@]}" >&2
    return 1
  fi

  ordered_ids=()
  for ((idx = 0; idx < ${#items[@]}; idx += 2)); do
    flag="${items[idx]}"
    value="${items[idx + 1]}"

    if [[ -n ${keyed_flags[$flag]:-} ]]; then
      identity="keyed:${flag}"
      if [[ -z ${seen_ids[$identity]:-} ]]; then
        ordered_ids+=("$identity")
        seen_ids[$identity]=1
      fi
      id_flag[$identity]="$flag"
      id_value[$identity]="$value"
      continue
    fi

    identity="pair:${flag}"$'\x1f'"$value"
    if [[ -n ${seen_ids[$identity]:-} ]]; then
      continue
    fi
    ordered_ids+=("$identity")
    seen_ids[$identity]=1
    id_flag[$identity]="$flag"
    id_value[$identity]="$value"
  done

  {
    printf '['
    for idx in "${!ordered_ids[@]}"; do
      identity="${ordered_ids[$idx]}"
      ((idx > 0)) && printf ','
      printf '%s\n' "${id_flag[$identity]}" | jq -R .
      printf ','
      printf '%s\n' "${id_value[$identity]}" | jq -R .
    done
    printf ']'
  }
}
