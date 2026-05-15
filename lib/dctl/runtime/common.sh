# shellcheck shell=bash
# Runtime adapter interface contract (sourced, not executed directly)
# Phase 0: skeleton only. Phase 1 fills in the dispatcher and rt_* funcs.

[[ -n ${_DCTL_RUNTIME_COMMON_LOADED:-} ]] && return 0
readonly _DCTL_RUNTIME_COMMON_LOADED=1

# Minimum libkrun version required by `dctl doctor` and the Phase 1 rt_* adapter.
# shellcheck disable=SC2034
readonly MIN_LIBKRUN_VER="1.18.0"

# Pinned tiny image for the decisive `podman run --runtime krun` smoke probe.
# TODO(phase-1): swap to digest pin.
# shellcheck disable=SC2034
readonly DCTL_DOCTOR_SMOKE_IMAGE="quay.io/quay/busybox:1.36"

# Interface contract — Phase 1 implements; doctor.sh does NOT call these in Phase 0.
#
#   rt_run   <image> [args...]      — start a container under the active runtime.
#   rt_exec  <ctr> <cmd> [args...]  — exec into a running container.
#   rt_ps    [filter...]            — list containers managed by dctl.
#   rt_rm    <ctr>                  — remove a container.
#   rt_build <ctxdir> -t <tag>      — build an image with the active runtime.
#
# Conformance contract: SPEC.md §5.5 and §1.3 (runtime-specific code MUST stay
# under lib/dctl/runtime/*; callers depend only on the rt_* surface).
