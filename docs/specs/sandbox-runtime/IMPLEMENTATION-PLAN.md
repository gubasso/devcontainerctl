# Sandbox Runtime — Implementation Plan (overview)

> Status: Complete
> Date: 2026-05-17
> Scope: Implement the `dctl` container runtime as **libkrun via `crun --krun`, fronted by rootless Podman** — podman-first throughout. The adapter shells out to `podman` directly; `dctl` interprets `devcontainer.json` itself.
> Companions: [SPEC.md](./SPEC.md), [DECISION.md](./DECISION.md), [DECISION-LINUX.md](./DECISION-LINUX.md), [RUNTIMES.md](./RUNTIMES.md), [COMPARISON-AI-AGENTS-SANDBOX.md](./COMPARISON-AI-AGENTS-SANDBOX.md)
> Reference implementation mined for working code: [`val4oss/ai-agents-sandbox`](https://github.com/val4oss/ai-agents-sandbox).

This document is the **stable overview** of the sandbox-runtime refactor. The per-phase execution briefs were ephemeral working notes used during implementation; durable outcomes are captured here and in the companion docs listed above.

## Context

The AI-agent threat model requires a real hardware-virtualization boundary. As recorded in [SPEC.md §1.5](./SPEC.md) and [DECISION-LINUX.md §1](./DECISION-LINUX.md), the shared-kernel container boundary is not adequate: November 2025 alone produced three back-to-back runc CVEs (CVE-2025-31133/-52565/-52881) each delivering full container breakout, and kernel LPEs land at roughly monthly cadence. [DECISION-LINUX.md §2](./DECISION-LINUX.md) commits the project to a single Linux backend — **libkrun via `crun --krun`, fronted by rootless Podman** — providing a KVM-class hardware boundary with the smallest plumbing surface among hardware-virt candidates.

## Preserved invariants (must not change)

- The OCI image authoring surface (`images/<name>/Containerfile`).
- The `devcontainer.json` + YAML manifest composition system (`devcontainers/`, `schemas/compose.schema.yaml`).
- Per-workspace container identity (work-clone isolation via the `devcontainer.local_folder` label).
- The XDG config layout (`~/.config/dctl`, `~/.cache/dctl`, `~/.local/share/dctl`).
- The user-facing `dctl init / deploy / test / ws / image / config` verbs.

## Scope decisions

1. **Thin adapter, single backend now.** Introduce `lib/dctl/runtime/{common.sh,krun.sh}` against the [SPEC.md §5.5](./SPEC.md) `rt_run / rt_exec / rt_ps / rt_rm / rt_build` interface; implement only the `krun` module. No `gvisor.sh` module in this plan.
2. **Own the lifecycle directly on top of `podman`.** The adapter shells out to `podman --runtime krun run / exec / ps / rm` and `podman build`, and interprets `devcontainer.json` lifecycle keys (`postCreateCommand`, `postStartCommand`, `remoteEnv`, `mounts`, `runArgs`) inside `lib/dctl/`. **Every container operation in the codebase invokes `podman` and nothing else** — no upstream `devcontainer` CLI dependency.
3. **Per-project workspace model preserved.** The `devcontainer.local_folder=$PWD` labeling and the per-clone container identity invariant from [SPEC.md §1.3](./SPEC.md) remain — Podman honors the same `--filter label=...` syntax.
4. **Tier 0 hygiene included.** Drop host `/tmp` bind, scoped/ephemeral token forwarding (replace `~/.config/gh` and `~/.claude*` bind mounts), `no-new-privileges`, `cap-drop=ALL`, **and** a default-deny egress allowlist. [SPEC.md §5.1](./SPEC.md).
5. **gVisor no-KVM CI fallback deferred** to a follow-up plan ([DECISION-LINUX.md §3](./DECISION-LINUX.md)); the adapter interface is shaped to accept it later without further refactor.

## Architecture overview

Post-Phase-1.5 layout (round `15a` introduces the helper tree; round `15b` extracts the command tree):

```
bin/dctl                              (dispatcher only — parses global opts, routes to group)
lib/dctl/
  ├── _lib/                           (internal helpers — one function per file)
  │     ├── source.sh                 (__dctl_require + __dctl_autoload_register primitives)
  │     ├── log.sh                    (log / warn / err / require_cmd)
  │     ├── paths.sh                  (XDG vars + workspace_*_path helpers)
  │     ├── fzf.sh                    (_fzf_pick)
  │     ├── workspace/                (canonical_name, resolve_config, label_filter, sibling, git_worktree)
  │     ├── registry/                 (file, lookup_manifest, lookup_discovery, validate, validate_manifest)
  │     ├── json/                     (strip_comments, merge_configs)
  │     ├── auth/                     (gh_token, glab_token, collect_env, ephemeral_creds — Phase 4)
  │     └── term/                     (collect_env)
  ├── commands/                       (one verb per file — autoloaded on demand)
  │     ├── ws/                       (_dispatch, up, reup, exec, shell, run, status, down)
  │     ├── image/                    (_dispatch, build, list, _helpers)
  │     ├── init/                     (_dispatch, do, _select_interactive, _generate_cache)
  │     ├── deploy/                   (_dispatch, all, list, plan, apply, reset, _discover)
  │     ├── config/                   (_dispatch only post-15b; register_project_defaults lives in _lib/registry/. Subverbs may land in a later round.)
  │     ├── test/                     (_dispatch, run, _summary)
  │     ├── doctor/                   (_dispatch, crun_libkrun, kvm, libkrun, subid, cgroups, podman_info, network_backend, userns, nested_virt — Phase 0)
  │     └── net/                      (_dispatch, allow, show, _default_allowlist, _user_allowlist, _compose — Phase 5)
  ├── lifecycle.sh                    (Phase 1: minimal devcontainer.json lifecycle interpreter)
  └── runtime/                        (adapter tree — kept flat until a second backend lands)
        ├── common.sh                 (interface contract; rt_* dispatcher on $DCTL_RUNTIME)
        └── krun.sh                   (podman + crun-krun implementation)
```

File-size discipline: ~200 lines/file soft target, 500 lines hard ceiling, helper sweet spot 30–80 lines. Sourcing model: eager (`_lib/source.sh`, `_lib/log.sh`, `_lib/paths.sh`), group-lazy (`commands/<group>/_dispatch.sh`), leaf-lazy (the verb file the user invoked + its declared helper deps). `dctl ws up` sources roughly 6–10 files; never the whole tree.

The user-facing surface (`devcontainer.json`, `*.yaml` manifests, `schemas/compose.schema.yaml`, CLI verbs) is unchanged. Layer composition and per-project workspace labeling are preserved verbatim.

Inside `krun.sh`, the lifecycle (all calls go to `podman` directly; no other container CLI is invoked anywhere in the codebase):

- `rt_run`: `podman run --runtime krun --detach --label devcontainer.local_folder=$PWD <runArgs from devcontainer.json> <image>`; on success, `lib/dctl/lifecycle.sh` runs `postCreateCommand` / `postStartCommand` via `podman exec`.
- `rt_exec`: `podman exec [--env K=V ...] -it <ctr> -- <cmd...>` with env forwarding for terminal + ephemeral tokens.
- `rt_ps`: `podman ps -a --filter label=devcontainer.local_folder=...`.
- `rt_rm`: `podman rm -f $(rt_ps -q ...)`.
- `rt_build`: `podman build --build-arg ... -t <tag> <path>`.
- `rt_image_inspect`: `podman image inspect <ref>` returning 0 on hit.

## Refactor history

The sandbox-runtime refactor landed in these implementation rounds:

- `00`: host preflight checks, `dctl doctor`, and install-path documentation.
- `10`: runtime adapter and lifecycle interpreter on top of rootless Podman and libkrun.
- `15a`: helper-tree extraction and lazy-loading dispatcher support.
- `15b`: command-tree extraction and structure-test enforcement.
- `20`: workspace and image commands rewired through the runtime adapter.
- `40`: tier-0 hygiene, ephemeral credential forwarding, and default-deny egress controls.
- `60`: test-suite expansion for runtime, auth-token forwarding, and network allowlists.
- `70`: manifest schema extensions (`runtime`, `runtime.resources`, `network.allow`), managed image `Containerfile` renames, documentation/spec sweep, and the CI grep gate that keeps legacy engine terminology from re-entering the tree.

## Verification

The refactor is complete when **all** of the following pass on an openSUSE Tumbleweed laptop with KVM available:

1. `make check` is clean (lint + bats + format).
2. `dctl doctor` reports a fully green preflight.
3. `dctl init && dctl deploy && dctl image build --all` succeeds against the `general` manifest. `podman images` lists `dctl-agents:latest` (or equivalent tag).
4. `dctl ws up` in a fresh workspace — **kernel-separation gate** (the load-bearing security claim of the migration; see [SPEC.md §4.1 "Residual host-kernel surface"](./SPEC.md)):
   - `podman inspect <ctr>` shows `"OCIRuntime": "krun"`.
   - In-guest `cat /proc/1/comm` shows `init.krun` (matches the ai-agents-sandbox sample output).
   - `dctl ws exec -- uname -r` returns a kernel release **distinct from** the host's `uname -r` (proves the guest runs `libkrunfw`'s bundled kernel, not the host kernel).
   - `dctl ws exec -- dmesg | grep -iE 'KVM|virtio'` shows virtio device init and does **not** list `virtio-gpu` (virgl/venus must remain off in this implementation).
5. `dctl ws exec -- env | grep GH_TOKEN` shows the forwarded short-lived token; `dctl ws exec -- ls ~/.config/gh` is **empty** (no host bind-mount of the full config dir).
6. `dctl ws exec -- curl -sS https://attacker.example.com` is **blocked** by the egress allowlist; `dctl ws exec -- curl -sS https://api.anthropic.com` succeeds.
7. `dctl ws exec -- mount | grep '^.* on /tmp '` shows tmpfs, not a host bind.
8. `dctl ws down` removes the container and cleans the ephemeral session tmpdir under `$DCTL_CACHE_DIR/sessions/`.
9. Two work-clones of the same repo produce two distinct containers (label-based identity preserved).
10. `bats tests/ --filter-tags integration` passes on the KVM host; non-integration tests pass everywhere.

## Out of scope (tracked, not built here)

- **gVisor no-KVM CI fallback** — deferred to a follow-up plan per scope decision #5. The adapter is shaped to accept a future `lib/dctl/runtime/gvisor.sh` without further refactor.
- **macOS / Apple `container` backend** — out of scope per [DECISION-LINUX.md §1](./DECISION-LINUX.md).
- **Bare Firecracker escape hatch** — catalog-only per [DECISION-LINUX.md §2.5](./DECISION-LINUX.md).
- **Kata-CH contingency adapter** — catalog-only per [DECISION-LINUX.md §7](./DECISION-LINUX.md).
- **Tier 3 inner-constraint relaxation** (default-strict seccomp once microVM is in place) — deferred per [SPEC.md §5.4](./SPEC.md).
- **Per-agent slim image builds** (ai-agents-sandbox `AGENT` build-arg pattern) — recommended for a subsequent iteration; not in this plan.
- **Single persistent home volume** model — incompatible with the per-project workspace invariant chosen in scope decision #3.
- **virtio-gpu (virgl/venus) enablement via `krun_set_gpu_options`** — explicitly **off** in this implementation. Enabling it would meaningfully widen the host-facing device-backend surface ([SPEC.md §4.1](./SPEC.md), [DECISION-LINUX.md §2.2](./DECISION-LINUX.md)). The round-10 smoke verification asserts `virtio-gpu` is **not** present in guest `dmesg`. If a future profile (e.g. local-inference / RamaLama-style) needs GPU passthrough, it must land as a separate, opt-in `agents-gpu` profile with its own threat-model review — not a flag flipped on the default path.

## Execution notes

- This plan was executed one round per `/prex` invocation. Each phase was independently committable; the execution briefs are now removed because the refactor is complete.
- **Round 10 (Phase 1) ships the lifecycle interpreter and the `podman` adapter together.** There is no fallback path — the lifecycle interpreter is the only path. `lib/dctl/lifecycle.sh` needs only the keys `dctl` actually consumes (`postCreateCommand`, `postStartCommand`, `remoteEnv`, `containerEnv`, `mounts`, `runArgs`, `remoteUser`, `workspaceFolder`, `workspaceMount`, `build`) — not the full Microsoft schema.
- **Rounds 15a + 15b (Phase 1.5) must run before rounds 20–70 touch any module they're going to rewrite.** They are pure rename/extract passes with no behavior change, so they commit cleanly between two semantic phases. Round 15b includes a one-time edit pass that re-anchors every pre-reorg line-number reference in the subsequent briefs (20, 40, 60, 70) so later rounds work against accurate paths.
- **Round 70 (Phase 7) closed the rename-and-docs sweep.** The grep gate remains the final acceptance bar: if any legacy container-engine reference survives outside the documented whitelist, the implementation is not done. CI enforces this gate going forward.
- ai-agents-sandbox is the closest available reference implementation of the same stack. Lift the preflight (`_check_microvm`), the libkrun version constant, the libkrun#674 workaround, and the resource-annotation defaults verbatim where they apply.
