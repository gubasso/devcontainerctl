# Sandbox Runtime — Implementation Plan (overview)

> Status: Active (execution in progress via per-round briefs under [`plans/`](plans/))
> Date: 2026-05-13
> Scope: Implement the `dctl` container runtime as **libkrun via `crun --krun`, fronted by rootless Podman** — podman-first throughout. The adapter shells out to `podman` directly; `dctl` interprets `devcontainer.json` itself.
> Companions: [SPEC.md](./SPEC.md), [DECISION.md](./DECISION.md), [DECISION-LINUX.md](./DECISION-LINUX.md), [RUNTIMES.md](./RUNTIMES.md), [COMPARISON-AI-AGENTS-SANDBOX.md](./COMPARISON-AI-AGENTS-SANDBOX.md)
> Reference implementation mined for working code: [`val4oss/ai-agents-sandbox`](https://github.com/val4oss/ai-agents-sandbox).

This document is the **stable overview** of the sandbox-runtime refactor. The per-phase execution detail lives in [`plans/`](plans/) as one `/prex` task brief per round. The briefs are ephemeral — each is deleted after its round merges, with durable content promoted to its permanent home elsewhere in the repo. See [`plans/README.md`](plans/README.md) for invocation, run order, and status.

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
  │     ├── init/                     (_dispatch, do, select_interactive, generate_cache)
  │     ├── deploy/                   (_dispatch, all, list, plan, apply, reset, _discover)
  │     ├── config/                   (_dispatch, register, unregister, list, show)
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

## Per-round briefs

Each `/prex` round consumes one brief from [`plans/`](plans/). Status is tracked in [`plans/README.md`](plans/README.md). Run sequentially:

- [x] **[00 — preflight-doctor](plans/00-preflight-doctor.md)** — Host preflight (`+LIBKRUN` build flag, `/dev/kvm`, kvm group, subuid/subgid, cgroups v2, network backend, nested-virt warn) + new `dctl doctor` sibling subcommand + new `docs/INSTALL.md`. Companion edits: `docs/QUICKSTART.md` Prerequisites block, `docs/CLAUDE.md` Quick Orientation block, `dctl test` deprecation banner.
- [x] **10 — runtime-adapter-and-lifecycle** — `lib/dctl/runtime/{common,krun}.sh` (the only backend) + `lib/dctl/lifecycle.sh` (the self-owned devcontainer.json interpreter) + close the `init.sh:84` merge-logic gap so `runArgs`/`workspaceMount`/`workspaceFolder` are first-class. Smoke verifies `init.krun` kernel separation.
- [ ] **[15a — helper-tree-and-autoload](plans/15a-helper-tree-and-autoload.md)** — Phase 1.5 part A: extract `lib/dctl/_lib/` (one function per file), rewrite `bin/dctl` around `__dctl_dispatch`, ship `lib/dctl/CLAUDE.md`.
- [ ] **[15b — command-tree-extraction](plans/15b-command-tree-extraction.md)** — Phase 1.5 part B: extract `commands/{ws,image,init,test,doctor,deploy,config}/` (one verb per file), add `tests/structure_test.bats` enforcing the layout invariants, re-anchor pre-reorg line numbers in subsequent briefs. `deploy.sh` (594 LOC) is the heaviest single module.
- [ ] **[20 — ws-and-image-adapter-rewire](plans/20-ws-and-image-adapter-rewire.md)** — Phases 2 + 3 combined: route every `dctl ws` and `dctl image` shell-out through `rt_*`. `commands/init/generate_cache.sh` emits the `--runtime krun` overlay + default krun resource annotations.
- [ ] **[40 — tier0-hygiene-and-egress](plans/40-tier0-hygiene-and-egress.md)** — Phases 4 + 5 combined: drop /tmp host bind, `--cap-drop=ALL`, `--security-opt=no-new-privileges`, ephemeral token forwarding (`_lib/auth/ephemeral_creds.sh`), new `docs/SECURITY.md`, default-deny egress allowlist via new `commands/net/*` + in-VM nftables (Option A).
- [ ] **[60 — test-suite](plans/60-test-suite.md)** — Phase 6: refactor `tests/dctl_test.bats` (1,749 LOC) to call into the adapter via mocks; add `tests/{runtime_krun,auth_token_forwarding,net_allowlist}_test.bats`; add a KVM-required `integration` smoke target.
- [ ] **[70 — renames-and-docs-sweep](plans/70-renames-and-docs-sweep.md)** — Phase 7: schema extensions (`runtime`, `runtime.resources`, `network.allow`), `git mv` Dockerfile → Containerfile (4 image files), top-level + sub-docs + legacy `spec/` sweep, final `Docker(file)?` grep gate (CI-enforced).

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

- This plan is **executed one round per `/prex` invocation**. Each phase is independently committable; commit cadence is one commit per round (the prex workflow may produce more than one commit if stage 4 review surfaces fixes).
- **Round 10 (Phase 1) ships the lifecycle interpreter and the `podman` adapter together.** There is no fallback path — the lifecycle interpreter is the only path. `lib/dctl/lifecycle.sh` needs only the keys `dctl` actually consumes (`postCreateCommand`, `postStartCommand`, `remoteEnv`, `containerEnv`, `mounts`, `runArgs`, `remoteUser`, `workspaceFolder`, `workspaceMount`, `build`) — not the full Microsoft schema.
- **Rounds 15a + 15b (Phase 1.5) must run before rounds 20–70 touch any module they're going to rewrite.** They are pure rename/extract passes with no behavior change, so they commit cleanly between two semantic phases. Round 15b includes a one-time edit pass that re-anchors every pre-reorg line-number reference in the subsequent briefs (20, 40, 60, 70) so later rounds work against accurate paths.
- **Round 70 (Phase 7) is non-optional and not a doc-only afterthought.** The grep gate at round 70 §9 is the final acceptance bar: if any `docker`/`Docker` reference survives outside the documented whitelist, the implementation is not done. CI enforces this gate going forward.
- ai-agents-sandbox is the closest available reference implementation of the same stack. Lift the preflight (`_check_microvm`), the libkrun version constant, the libkrun#674 workaround, and the resource-annotation defaults verbatim where they apply.
