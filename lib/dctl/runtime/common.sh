# shellcheck shell=bash
# Runtime adapter interface contract (sourced, not executed directly)

[[ -n ${_DCTL_RUNTIME_COMMON_LOADED:-} ]] && return 0
readonly _DCTL_RUNTIME_COMMON_LOADED=1

: "${DCTL_RUNTIME:=krun}"

# Minimum libkrun version required by `dctl doctor` and the Phase 1 rt_* adapter.
# shellcheck disable=SC2034
readonly MIN_LIBKRUN_VER="1.18.0"

# Pinned tiny image for the decisive `podman run --runtime krun` smoke probe.
# TODO(phase-1): swap to digest pin.
# shellcheck disable=SC2034
readonly DCTL_DOCTOR_SMOKE_IMAGE="quay.io/quay/busybox:1.36"

# Interface contract — callers depend only on these runtime-agnostic entrypoints.
#
#   rt_run            <workspace_folder> <config_path> [extra_args...]
#     Start a detached container for the workspace under the active runtime.
#     Extra args are appended after merged runArgs and before the image.
#
#   rt_exec           <workspace_folder> <config_path> [--env K=V ...] -- <cmd...>
#     Execute a command inside the workspace container under the active runtime.
#
#   rt_ps             [--quiet | --format <go-template>] [--running] <workspace_folder>
#     List containers managed by dctl for the workspace.
#       --quiet              IDs only.
#       --format <template>  Pass-through to `podman ps --format`.
#       --running            Only list running containers (omit `-a`).
#
#   rt_rm             <workspace_folder>
#     Remove all containers managed by dctl for the workspace.
#
#   rt_build          <image_name> <context_dir> [--build-arg K=V ...]
#     Build a local image with the active runtime backend's builder.
#
#   rt_image_inspect  <image_ref>
#     Return 0 if the image exists locally; return non-zero otherwise.
#
# Conformance contract: SPEC.md §5.5 and §1.3 (runtime-specific code MUST stay
# under lib/dctl/runtime/*; callers depend only on the rt_* surface).

_rt_unsupported_runtime() {
  err "Unsupported DCTL_RUNTIME='${DCTL_RUNTIME}' (only 'krun' is implemented; see DECISION-LINUX.md §5)"
}

rt_run() {
  case "$DCTL_RUNTIME" in
    krun) _krun_rt_run "$@" ;;
    *) _rt_unsupported_runtime ;;
  esac
}

rt_exec() {
  case "$DCTL_RUNTIME" in
    krun) _krun_rt_exec "$@" ;;
    *) _rt_unsupported_runtime ;;
  esac
}

rt_ps() {
  case "$DCTL_RUNTIME" in
    krun) _krun_rt_ps "$@" ;;
    *) _rt_unsupported_runtime ;;
  esac
}

rt_rm() {
  case "$DCTL_RUNTIME" in
    krun) _krun_rt_rm "$@" ;;
    *) _rt_unsupported_runtime ;;
  esac
}

rt_build() {
  case "$DCTL_RUNTIME" in
    krun) _krun_rt_build "$@" ;;
    *) _rt_unsupported_runtime ;;
  esac
}

rt_image_inspect() {
  case "$DCTL_RUNTIME" in
    krun) _krun_rt_image_inspect "$@" ;;
    *) _rt_unsupported_runtime ;;
  esac
}
