# Phase 10 — Runtime adapter scaffolding + minimal lifecycle interpreter (prex task brief)

> Status: Pending
> Companion docs (Codex must read these in stage 1):
> - [docs/specs/sandbox-runtime/SPEC.md](../SPEC.md) (§4.1 "Residual host-kernel surface", §5.5 adapter interface, §320 cross-runtime-keys policy)
> - [docs/specs/sandbox-runtime/DECISION.md](../DECISION.md)
> - [docs/specs/sandbox-runtime/DECISION-LINUX.md](../DECISION-LINUX.md) (§2.2 device-set delta, §5 single-backend invariant)
> - [docs/specs/sandbox-runtime/RUNTIMES.md](../RUNTIMES.md)
> - [docs/specs/sandbox-runtime/IMPLEMENTATION-PLAN.md](../IMPLEMENTATION-PLAN.md) (master overview)
> Reference implementation: [`val4oss/ai-agents-sandbox`](https://github.com/val4oss/ai-agents-sandbox) — lift the libkrun#674 Copilot HTTP/2 vsock workaround (`ai-agents-sandbox.sh:259-263`) and the resource annotation defaults (`:301-302`).
> Depends on: [`00-preflight-doctor.md`](00-preflight-doctor.md) — must be `Done`. `lib/dctl/runtime/common.sh` must exist with `MIN_LIBKRUN_VER=1.18.0`.
> Output of this round: `dctl ws up` runs under `podman --runtime krun` end-to-end; the guest workload is provably **not** on the host kernel.

## Task

Introduce the runtime-adapter abstraction layer and a self-owned `devcontainer.json` lifecycle interpreter on top of `podman` directly. There is no upstream `devcontainer` CLI dependency anywhere — the user-facing `devcontainer.json` schema is consumed inside `lib/dctl/` and translated into `podman run / exec` invocations. Phase 0 already created `lib/dctl/runtime/common.sh` as a skeletal file holding `MIN_LIBKRUN_VER`; this round fills it in with the full `rt_*` dispatcher, lands the `krun.sh` backend implementation, and adds the lifecycle interpreter at `lib/dctl/lifecycle.sh`. Close the long-standing merge-logic gap at `lib/dctl/init.sh:84` that does not honor `runArgs`/`workspaceMount`/`workspaceFolder` — Phase 4's `--cap-drop=ALL` + tmpfs entry depend on `runArgs` being a first-class merged key.

## Preconditions (must already be true on `develop`)

- Phase 0 (`00-preflight-doctor.md`) has shipped: `dctl doctor` is green on the developer's host, `lib/dctl/runtime/common.sh` exists with `MIN_LIBKRUN_VER=1.18.0`, `bin/dctl` has a `doctor)` arm.
- `make check` is currently green on `develop`.
- `bin/dctl:14-20` is still the pre-Phase-1.5 eager-source block (Phase 1.5 has not run yet).

## Scope (in this round)

- **Edit:** `lib/dctl/runtime/common.sh` — fill in the `rt_*` interface dispatcher.
- **New file:** `lib/dctl/runtime/krun.sh` — the only backend (Podman + crun-krun).
- **New file:** `lib/dctl/lifecycle.sh` — the self-owned devcontainer.json lifecycle interpreter.
- **Edit:** `bin/dctl` — source the new `runtime/common.sh`, `runtime/krun.sh`, and `lifecycle.sh` from the module-source block at `bin/dctl:14-20`.
- **Edit:** `lib/dctl/init.sh` (around `:84`) — close the merge-logic gap so `runArgs`, `workspaceMount`, `workspaceFolder` are honored as first-class merged keys. Per SPEC.md §320, unsupported cross-runtime keys must error clearly rather than silently degrade.
- **Smoke verification** on the developer's KVM-capable openSUSE Tumbleweed host (gates listed below).

## Out of scope for this round (DO NOT touch)

- Routing `dctl ws` / `dctl image` verbs through `rt_*` — Phase 2/3's job (round `20`). This round only lands the adapter and proves it works via a stand-alone smoke test; existing `dctl ws` and `dctl image` keep calling `docker`/`devcontainer` as before.
- The Phase 1.5 code reorganization — round `15a`/`15b`. `runtime/{common,krun}.sh` and `lifecycle.sh` land in the **flat** layout this round; they are preserved verbatim across Phase 1.5.
- Tier 0 hygiene flags (`--cap-drop=ALL`, `--security-opt=no-new-privileges`, tmpfs) — Phase 4's job (round `40`). The lifecycle interpreter parses `runArgs` but does not inject these flags itself.
- The egress allowlist (`commands/net/*`) — Phase 5's job (round `40`).
- gVisor fallback — out of scope for the entire plan ([DECISION-LINUX.md §3](../DECISION-LINUX.md)).
- virtio-gpu enablement — explicitly **off**; the smoke test asserts `virtio-gpu` is **not** present in guest `dmesg`.

## Implementation guidance

### `lib/dctl/runtime/common.sh` — adapter contract

Replace the Phase-0 skeleton with the full interface contract. The dispatcher dispatches on `DCTL_RUNTIME` (default `krun`); any other value errors explicitly per [DECISION-LINUX.md §5](../DECISION-LINUX.md):

```sh
# rt_run            <workspace_folder> <config_path> [extra_args...]
# rt_exec           <workspace_folder> <config_path> [--env K=V ...] -- <cmd...>
# rt_ps             [--quiet] <workspace_folder>
# rt_rm             <workspace_folder>
# rt_build          <image_name> <context_dir> [--build-arg K=V ...]
# rt_image_inspect  <image_ref>   # returns 0 if image exists locally
```

`MIN_LIBKRUN_VER` stays exactly as Phase 0 set it.

### `lib/dctl/runtime/krun.sh` — the backend

- **Memoized preflight:** call into `dctl doctor`'s probe set once per session (cache the result on a `_DCTL_KRUN_PREFLIGHT_OK` shell var). Don't re-run on every `rt_*` call.
- **`rt_run`** reads the resolved `devcontainer.json` (via the existing config-resolution path in `lib/dctl/common.sh:196-259` — `resolve_devcontainer_config`), extracts `runArgs`, `mounts`, `remoteEnv`, `containerEnv`, `image`, and the `build` block. The build-file path points at `images/<name>/Containerfile` (or `Dockerfile` until Phase 7 renames). Emits: `podman run --runtime krun --detach --label devcontainer.local_folder=$PWD <runArgs> --mount type=... <image>`. On success calls `lib/dctl/lifecycle.sh run_postcreate <ctr>` then `lib/dctl/lifecycle.sh run_poststart <ctr>`.
- **`rt_exec`** translates `remoteEnv` into `podman exec --env K=V` flags. Pass `-it` when stdin is a TTY (mirror existing `ws.sh:118-127 devcontainer_exec` behavior). Forward terminal env (`TERM`, `COLORTERM`) and ephemeral auth tokens (`GH_TOKEN`, `GITLAB_TOKEN`) — the existing `auth.sh:12-58` helpers already build the env list; reuse them.
- **`rt_ps`** wraps `podman ps -a --filter label=devcontainer.local_folder=...`. `--quiet` toggles `-q`. The label filter is identical to the current Docker filter at `lib/dctl/common.sh:82-84` (`workspace_label_filter`) — **verify** Podman honors the same `--filter label=...` syntax before declaring done; it does, but the test must run.
- **`rt_rm`** = `podman rm -f $(rt_ps -q <ws>)`. No-op if no containers.
- **`rt_build`** shells to `podman build` directly with `--build-arg`, `--secret id=gh_token,src=<path>`, and `--tag`. Containerfile `RUN --mount=type=secret,id=gh_token ...` lines are OCI-frontend-compatible; no Containerfile edits needed.
- **`rt_image_inspect`** = `podman image inspect <ref> >/dev/null 2>&1`; returns 0 on hit.
- **libkrun #674 workaround:** if the agents image bundles Copilot CLI, port `ai-agents-sandbox.sh:259-263`'s vsock fix into `rt_run` (env-var or sysctl that disables HTTP/2 for the affected paths). Reference: <https://github.com/containers/libkrun/issues/674> (still open 2026-05).
- **Default krun resources:** annotate `krun.ram_mib=4096`, `krun.cpus=2` (matches ai-agents-sandbox `:301-302`). Make overridable via a future `runtime.resources` block in the manifest schema — Phase 7 adds the schema; for now hardcode the defaults.

### `lib/dctl/lifecycle.sh` — the lifecycle interpreter

- `run_postcreate <ctr>` and `run_poststart <ctr>` read the cached resolved `devcontainer.json`, look up `postCreateCommand` / `postStartCommand` (string, array, or object form per upstream schema), and exec each via `podman exec`.
- Honor `remoteUser`, `workspaceFolder`, `workspaceMount` from the resolved config.
- This is the **entire** devcontainer.json surface `dctl` consumes. The rest of the Microsoft schema (`features`, `customizations`, IDE-extension lists) is ignored by design — `dctl` is not an IDE-extension installer.

### `lib/dctl/init.sh` — merge-logic gap (close it here)

`lib/dctl/init.sh:84` currently merges only `mounts`, `postCreateCommand`, `containerEnv`, `remoteEnv` (documented at `devcontainers/README.md:90`). It does **not** special-case `runArgs`, `workspaceMount`, `workspaceFolder`. Extend the merge to honor those three keys:

- `runArgs` — concatenated across layers (deduplicate flag-value pairs, preserve order, last-layer-wins for conflicting `--name`/`--label` etc.).
- `workspaceMount` — last-layer-wins (string, not array).
- `workspaceFolder` — last-layer-wins.

Per [SPEC.md §320](../SPEC.md), if a layer specifies a cross-runtime key the adapter cannot honor (e.g. a future `runtime: gvisor` value when only `krun` is implemented), error clearly with the offending layer + key.

### `bin/dctl` wiring

Add three source lines next to the existing module-source block at `bin/dctl:14-20`:

```sh
source "${DCTL_LIB_DIR}/runtime/common.sh"
source "${DCTL_LIB_DIR}/runtime/krun.sh"
source "${DCTL_LIB_DIR}/lifecycle.sh"
```

No dispatcher changes — `rt_*` are called from `ws.sh`/`image.sh` in Phase 2/3, not from `bin/dctl` directly.

## Smoke verification (KVM-capable openSUSE Tumbleweed host)

The kernel-separation check is the **load-bearing security claim** of the entire migration ([SPEC.md §4.1](../SPEC.md)):

- `podman run --runtime krun --rm <agents-image> echo ok` succeeds, AND:
  - `podman inspect <ctr> --format '{{.OCIRuntime}}'` → `krun`.
  - In-guest `cat /proc/1/comm` → `init.krun` (matches ai-agents-sandbox reference output).
  - In-guest `uname -r` returns a **different** kernel release than the host's `uname -r` (proves `libkrunfw`-bundled kernel, not host kernel).
  - In-guest `dmesg | grep -iE 'KVM|virtio'` lists `virtio-fs`, `virtio-vsock`, `virtio-net`, `virtio-console` — and **does not** list `virtio-gpu` (virgl/venus must remain unused).
- `rt_exec` round-trip: interactive TTY (`-it`), env forwarding, `gh auth token` round-trip.
- `rt_build` produces images that work in the above flow.
- If Copilot CLI is in the agents image: HTTP/2 traffic to `api.githubcopilot.com` does not trigger the libkrun #674 BufDescTooSmall failure mode (port the workaround if it does).

## Acceptance gates (all must pass before stage 4 review approves)

- `make check` passes (lint + bats + format).
- `lib/dctl/runtime/common.sh` declares the full `rt_*` interface and dispatches on `DCTL_RUNTIME` with explicit error on non-`krun` values.
- `lib/dctl/runtime/krun.sh` exists and implements all six `rt_*` functions.
- `lib/dctl/lifecycle.sh` exists and exposes `run_postcreate` + `run_poststart`.
- `bin/dctl` sources the three new files.
- `lib/dctl/init.sh:84` merge extension covers `runArgs`, `workspaceMount`, `workspaceFolder` (verify with a unit test if one already exists in `tests/dctl_test.bats`, otherwise add a smoke assertion).
- Smoke verification above passes on the developer's KVM host. **The `init.krun` and `uname -r` checks are the load-bearing acceptance criteria — do not declare done if either fails.**
- No `dctl ws` or `dctl image` call sites have been edited (Phase 2/3 work).

## Risks & known gotchas

- **libkrun #674 is open.** If Copilot CLI is in the agents image and the in-VM kernel is ≥ 6.2, large HTTPS request bodies fail with BufDescTooSmall. Port the workaround from `ai-agents-sandbox.sh:259-263` into `rt_run`. Reconfirm issue status: <https://github.com/containers/libkrun/issues/674>.
- **crun #1894** (`/dev/kvm` posix-ACL) can make `rt_run` fail even when `dctl doctor` showed `/dev/kvm` rw + kvm group. The doctor's `getfacl /dev/kvm` warn-only check from Phase 0 surfaces this; do not silently retry.
- **`virtio-gpu` must remain off.** The smoke verification asserts it. Do not enable `krun_set_gpu_options` even if a future profile wants GPU; that lands as a separate opt-in `agents-gpu` profile with its own threat-model review.
- **Label-filter compatibility** — Podman honors `--filter label=...` identically to Docker, but the assumption is load-bearing for work-clone identity. The smoke run must include `rt_ps` on a real container to verify.
- **Network backend pinning** — `dctl doctor` (Phase 0) surfaces the active backend. Phase 2 will emit `--network` flags. This round does not pin a backend in `rt_run`; the default Podman backend is fine for the smoke test, but record the host's active backend in the smoke log for Phase 2's reference.

## Plan-file cleanup (Codex must perform in stage 3, as part of the implementation commit)

1. Delete this file: `docs/specs/sandbox-runtime/plans/10-runtime-adapter-and-lifecycle.md`.
2. Update `docs/specs/sandbox-runtime/plans/README.md`: this round's row `Status` → `Done — <commit-sha> — <date>`.
3. Promote durable content:
   - The `rt_*` interface contract comments live permanently in `lib/dctl/runtime/common.sh`.
   - The lifecycle interpreter's accepted-key list is documented in source comments of `lib/dctl/lifecycle.sh` (no separate doc).
   - If a notable adapter design decision came up during stage 3 (e.g. how `runArgs` deduplication handles `--label` conflicts), append a short note to `docs/specs/sandbox-runtime/DECISION-LINUX.md`.
4. Update `docs/specs/sandbox-runtime/IMPLEMENTATION-PLAN.md`: tick the Phase 1 row in the `## Per-round briefs` section.
