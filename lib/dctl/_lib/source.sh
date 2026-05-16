# shellcheck shell=bash
# Source-once primitives + lazy dispatch for dctl modules.

[[ -n ${_DCTL_SOURCE_LOADED:-} ]] && return 0
readonly _DCTL_SOURCE_LOADED=1

: "${DCTL_LIB_DIR:?DCTL_LIB_DIR must be set before sourcing _lib/source.sh}"

__dctl_require() {
  local rel="$1" abs guard
  [[ -n $rel ]] || {
    printf '\033[1;31mERROR:\033[0m __dctl_require needs a relative path\n' >&2
    exit 1
  }
  abs="${DCTL_LIB_DIR}/${rel}"
  guard="_DCTL_LOADED_${rel//[^A-Za-z0-9_]/_}"
  [[ -n ${!guard:-} ]] && return 0
  [[ -r $abs ]] || {
    printf '\033[1;31mERROR:\033[0m Missing dctl library file: %s\n' "$abs" >&2
    exit 1
  }
  printf -v "$guard" '%s' 1
  readonly "$guard"
  # shellcheck source=/dev/null
  source "$abs"
}

declare -gA __dctl_autoload_registry=()

__dctl_autoload_register() {
  local func="$1" rel="$2"
  __dctl_autoload_registry["$func"]="$rel"
  eval "${func}() { unset -f ${func}; __dctl_require '${rel}'; ${func} \"\$@\"; }"
}

__dctl_dispatch() {
  local group="${1:-help}"

  case "$group" in
    "" | help | -h | --help)
      usage
      return 0
      ;;
    version | -v | --version)
      printf 'dctl %s\n' "${DCTL_VERSION:-dev}"
      return 0
      ;;
  esac

  shift

  # Allow-list of real CLI command groups. Internal shims like `common`,
  # `auth`, `lifecycle`, or `runtime/*` must not be reachable via the
  # dispatcher even though their flat files are readable under
  # ${DCTL_LIB_DIR}. Round 15b will replace this with `commands/<group>/`
  # discovery once each group has its own `_dispatch.sh`.
  case "$group" in
    init | deploy | test | doctor | ws | image | config) ;;
    *)
      printf '\033[1;31mERROR:\033[0m Unknown command group: %s\n' "$group" >&2
      exit 1
      ;;
  esac

  local cmd_dispatch="${DCTL_LIB_DIR}/commands/${group}/_dispatch.sh"
  if [[ -r $cmd_dispatch ]]; then
    __dctl_require "commands/${group}/_dispatch.sh"
    "main_${group}" "$@"
    return $?
  fi

  local flat="${DCTL_LIB_DIR}/${group}.sh"
  if [[ -r $flat ]]; then
    __dctl_require "${group}.sh"
    "main_${group}" "$@"
    return $?
  fi

  printf '\033[1;31mERROR:\033[0m Unknown command group: %s\n' "$group" >&2
  exit 1
}
