# Sandbox Runtime — `dctl` vs. ai-agents-sandbox

> Status: Informational comparison  
> Date: 2026-05-13  
> Scope: Technical comparison between the `dctl` runtime defined in [DECISION-LINUX.md](./DECISION-LINUX.md) — libkrun via `crun --krun` fronted by rootless Podman — and the existing [val4oss/ai-agents-sandbox](https://github.com/val4oss/ai-agents-sandbox) project, which ships the same runtime stack as a single-purpose agent sandbox. The comparison covers the runtime/security layer and the end-user UX / config-composability surface to determine whether the two initiatives overlap.  
> Companions: [DECISION-LINUX.md](./DECISION-LINUX.md), [DECISION.md](./DECISION.md), [SPEC.md](./SPEC.md), [RUNTIMES.md](./RUNTIMES.md), [COMPARISON-FLAKE-PILOT.md](./COMPARISON-FLAKE-PILOT.md).

## 0. Summary

| Axis | `dctl` (per `DECISION-LINUX.md`) | ai-agents-sandbox (shipped today) |
|---|---|---|
| Boundary class | **KVM microVM** ([DECISION-LINUX.md §2.2](./DECISION-LINUX.md)) | **KVM microVM** when `/dev/kvm` + libkrun are present; shared-kernel container in the `no-microvm` fallback |
| Runtime stack | `podman --runtime krun` → `crun --krun` → libkrun ([DECISION-LINUX.md §2.1](./DECISION-LINUX.md)) | Same: `podman --runtime krun` → `crun-krun` → libkrun; falls back to plain `podman` + `slirp4netns` |
| Networking | TSI (no host-side TAP/bridge/NAT/`slirp4netns`) ([DECISION-LINUX.md §2.1](./DECISION-LINUX.md)) | TSI in microvm mode; `slirp4netns` in fallback |
| Privilege model | Rootless Podman ([DECISION-LINUX.md §2.3](./DECISION-LINUX.md), [SPEC.md §5.2](./SPEC.md)) | Rootless Podman |
| Egress policy | Runtime-agnostic Tier-0 allowlist shipped by `dctl` ([SPEC.md §5.2](./SPEC.md)) | None |
| Scope / product shape | Multi-project devcontainer composition system; the agent sandbox is **one preset** ([SPEC.md §1.3](./SPEC.md)) | Single-purpose agent runner: one image (or per-agent slim variant), one container, one persistent home volume |
| OS coverage | Linux-only ([DECISION-LINUX.md §1](./DECISION-LINUX.md)) | Linux primary; macOS via Podman Machine + Apple Hypervisor.framework |
| Status | Planned. Libkrun adapter is the open milestone in [DECISION-LINUX.md §7](./DECISION-LINUX.md) / [SPEC.md §6](./SPEC.md). | Shipping. Working `_check_microvm` probe, libkrun ≥ 1.18 version gate, [libkrun#674](https://github.com/containers/libkrun/issues/674) Copilot workaround, and macOS fallback in ~419 LOC of POSIX shell. |

**Verdict.** Same boundary class, same concrete runtime stack, different abstraction levels. `dctl`-planned and ai-agents-sandbox are **not in a replacement relationship**: ai-agents-sandbox is structurally a narrower implementation of what `dctl`-planned will offer as one preset. Today, ai-agents-sandbox is the closest available reference implementation of the libkrun adapter sketched in [SPEC.md §5.5](./SPEC.md) and slated as the T2.0 / T2.1c milestone in [SPEC.md §6](./SPEC.md) / [DECISION-LINUX.md §7](./DECISION-LINUX.md). Once that adapter lands, ai-agents-sandbox's surface is reproducible inside `dctl` as one manifest plus a slim image; the runtime/security layer is fully overlapping, while the UX/composability layer overlaps only on the single-sandbox slice `dctl` will preset.

---

## 1. The two projects

### 1.1 `dctl` (planned)

The `dctl` runtime is defined by [DECISION-LINUX.md](./DECISION-LINUX.md): a single Linux backend (libkrun via `crun --krun`, fronted by rootless Podman) and a no-KVM CI fallback (gVisor). The decision narrows the cross-platform catalog in [DECISION.md](./DECISION.md) to the one shippable backend on Linux ([DECISION-LINUX.md §0](./DECISION-LINUX.md)). The premises committed to by [SPEC.md §1](./SPEC.md) are: KVM-class hardware-virt boundary against adversarial code ([SPEC.md §1.2](./SPEC.md)), end-user ergonomics minimal enough to support multi-project workflows ([SPEC.md §1.3](./SPEC.md)), and explicit rejection of shared-kernel containers as the workstation boundary ([SPEC.md §1.4](./SPEC.md), [SPEC.md §1.5](./SPEC.md)). The runtime-abstraction adapter contract is sketched in [SPEC.md §5.5](./SPEC.md); the libkrun adapter is milestone T2.0 / T2.1c in [SPEC.md §6](./SPEC.md) and [DECISION-LINUX.md §7](./DECISION-LINUX.md). The composition/manifest/CLI layer above the runtime is being refactored — only the spec set is load-bearing on the `dctl` side of this comparison.

### 1.2 ai-agents-sandbox (shipped)

[val4oss/ai-agents-sandbox](https://github.com/val4oss/ai-agents-sandbox) is a 419-line POSIX-shell driver around `podman build` and `podman run`, plus a single openSUSE-Tumbleweed `Containerfile`. The README states the goal as *"a secure, isolated environment for running AI coding agents (GitHub Copilot, Gemini CLI, Claude Code) on openSUSE Tumbleweed using rootless container (Podman) and microvm (libkrun)"* (`README.md:1-9`). The `AGENTS.md` mission orders project goals as: *"(1) Generate a full securized, isolated environment, foolproof against all host data exploits. (2) Be easy to use, should be adapted for no-technical person. (3) Should not slowdown developer productivity."* (`AGENTS.md:45-50`). The image layout is conventional Podman: `image/Containerfile`, `image/scripts/entrypoint.sh`, `image/skel/.gitconfig`, `image/agents/<agent>/` (sub-agent markdown definitions), and `image/.krun_vm.json` (microVM resource defaults) — see `AGENTS.md:31-36`.

---

## 2. Isolation / threat model

| Axis | `dctl` (planned) | ai-agents-sandbox |
|---|---|---|
| Kernel sharing host ↔ guest | None in libkrun mode. Guest kernel under KVM. ([DECISION-LINUX.md §2.2](./DECISION-LINUX.md), [RUNTIMES.md §4.4](./RUNTIMES.md)) | None in libkrun mode. Shared kernel only on `no-microvm` opt-out (`ai-agents-sandbox.sh:273-276`) or on macOS where Podman Machine itself provides a Hypervisor.framework boundary (`README.md:401-417`). |
| Boundary class | KVM microVM. | KVM microVM (microvm mode); shared-kernel + namespaces + seccomp (fallback). |
| runc / shared-kernel CVE applicability | Eliminated at the primary boundary; the Nov-2025 runc cluster does not apply ([DECISION-LINUX.md §1](./DECISION-LINUX.md), [Sysdig](https://www.sysdig.com/blog/runc-container-escape-vulnerabilities), [CNCF](https://www.cncf.io/blog/2025/11/28/runc-container-breakout-vulnerabilities-a-technical-overview/)). | Eliminated in microvm mode; applies inside the shared-kernel fallback. |
| Host-side networking surface | **TSI** removes host TAP/bridge/NAT/`slirp4netns` entirely. ([DECISION-LINUX.md §2.1](./DECISION-LINUX.md)) | TSI in microvm mode; `--network slirp4netns` (user-mode NAT) in fallback (`ai-agents-sandbox.sh:304`, `README.md:351-358`). |
| Cap / syscall posture | Tier-0 policy: `--cap-drop=ALL`, `--no-new-privileges`, scoped/ephemeral mounts, `userns=auto:size=65536`, default seccomp; runtime-agnostic ([SPEC.md §5.2](./SPEC.md), [DECISION-LINUX.md §2.3](./DECISION-LINUX.md)). | Already enforced today: `--cap-drop ALL`, `--security-opt no-new-privileges`, `--userns=keep-id`, `--tmpfs /tmp:rw,nosuid,size=1g`, `--pids-limit 1024`, Podman default seccomp (`ai-agents-sandbox.sh:291-300`, `README.md:341-368`). |
| KVM / libkrun preflight | Required: detect KVM, surface a clear error when missing ([DECISION-LINUX.md §2.3](./DECISION-LINUX.md)). Probe implementation is part of the open T2.0 milestone ([SPEC.md §6](./SPEC.md), [DECISION-LINUX.md §7](./DECISION-LINUX.md)). | Implemented: `_check_microvm` probes `/usr/bin/krun`, libkrun ≥ 1.18 (gates on commit [`757b080b`](https://github.com/containers/libkrun/commit/757b080b4c5f5934f8e5320a38b401aaec116764)), `/dev/kvm`, `kvm` group membership, and warns on missing nested-virt (`ai-agents-sandbox.sh:102-156`; `MIN_LIBKRUN_VER` declared at `ai-agents-sandbox.sh:45`). |
| Known libkrun bug routed around | Not yet specified. | Detects the Copilot CLI HTTP/2 vsock `BufDescTooSmall` bug and falls back to `no-microvm` for the `copilot` agent (`ai-agents-sandbox.sh:259-263`); tracks [containers/libkrun#674](https://github.com/containers/libkrun/issues/674). |
| Egress policy | Tier-0 egress allowlist, runtime-agnostic, shipped by `dctl` ([SPEC.md §5.2](./SPEC.md), [SPEC.md §6 Tier 0](./SPEC.md)). | None. Outbound traffic is unfiltered in both microvm (TSI) and fallback (`slirp4netns`) modes. |
| Credential / token model | Tier-0 replaces host-config bind-mounts with scoped, ephemeral token forwarding ([SPEC.md §5.2](./SPEC.md), [DECISION-LINUX.md §6 risk 5](./DECISION-LINUX.md)). | No host-config bind-mounts at all. Auth happens *inside* the container and persists to the sandbox volume (`README.md:369-376`, `README.md:443-468`). |
| Resource limits | Not specified at the runtime layer. | `--annotation krun.ram_mib=4096 --annotation krun.cpus=2` in microvm mode (`ai-agents-sandbox.sh:301-302`); also configurable via `image/.krun_vm.json` (`README.md:423-435`). |
| OS support | Linux-only ([DECISION-LINUX.md §1](./DECISION-LINUX.md), [DECISION-LINUX.md §4](./DECISION-LINUX.md)). | Linux primary; macOS detected and handled explicitly via Podman Machine + Apple Hypervisor.framework (`ai-agents-sandbox.sh:249-256`, `README.md:401-417`). |
| CI parity for KVM-less environments | gVisor (`runsc`), documented as fallback only ([DECISION-LINUX.md §3](./DECISION-LINUX.md), [RUNTIMES.md §3.1](./RUNTIMES.md)). | No equivalent. Falls back to shared-kernel Podman + `slirp4netns` on `no-microvm`. |

**Runtime / security verdict.** The two projects sit in the same boundary class with the same concrete runtime stack on the primary path. Differences are operational-layer concerns: ai-agents-sandbox already implements the preflight, version-gating, and known-bug workaround code the `dctl` T2.0 milestone needs; `dctl` commits to runtime-agnostic Tier-0 policies (egress allowlist, scoped token forwarding) that ai-agents-sandbox does not yet ship; ai-agents-sandbox additionally covers macOS via Podman Machine, which is explicitly out of scope for `dctl` per [DECISION-LINUX.md §4](./DECISION-LINUX.md).

---

## 3. End-user UX / command API

| Axis | `dctl` (planned, spec-level) | ai-agents-sandbox (shipped) |
|---|---|---|
| Entry point | CLI shape is being refactored. The load-bearing contract is the runtime-abstraction interface in [SPEC.md §5.5](./SPEC.md) (`rt_run`, `rt_exec`, `rt_ps`, `rt_rm`, `rt_build`); the ergonomics premises are [SPEC.md §1.3](./SPEC.md). | Single POSIX script: `ai-agents-sandbox.sh <action> [agent] [no-microvm\|all]` (`ai-agents-sandbox.sh:163-185`). |
| Top-level actions | To be defined during the refactor. | `build`, `run`, `clean`, `status` (`ai-agents-sandbox.sh:163-185`, `README.md:142-158`). |
| Sandbox selection | Manifest-driven (per the composition premises in [SPEC.md §1.3](./SPEC.md)); exact schema being refactored. | Positional `<agent>` argument switches both image name and container name to the per-agent slim variant (`ai-agents-sandbox.sh:401-411`). |
| Per-project model | Each project gets its own workspace identity ([SPEC.md §1.3](./SPEC.md)). | One persistent home volume (`$CTN_NAME-home`) plus a bind-mounted `workspace/` (`ai-agents-sandbox.sh:238-247, 289-294`); all projects live inside `~/workspace`. Cloning happens *inside* the container (`README.md:283-291`). |
| Auth / token model | Tier-0 scoped/ephemeral token forwarding from the host ([SPEC.md §5.2](./SPEC.md)). | Auth performed inside the container; tokens persisted to `sandbox/.config/gh/`, `sandbox/.gemini/`, `sandbox/.claude/` (`README.md:443-468`). No host-side token extraction. |
| Onboarding friction | Requires KVM + rootless Podman + libkrun on Linux; exact install path defined during the refactor. Help-text contract: clear error when KVM is missing ([DECISION-LINUX.md §2.3](./DECISION-LINUX.md)). | Podman + `slirp4netns` mandatory; `crun ≥ 1.22`, `libkrun ≥ 1.17`, `libkrunfw ≥ 5`, `/dev/kvm`, `kvm` group for secure mode (`README.md:34-85`). Helpful per-failure error messages from `_check_microvm` (`ai-agents-sandbox.sh:102-156`). |
| Target audience | Developers running AI agents across multi-language / multi-project / multi-clone workflows ([SPEC.md §1.3](./SPEC.md)). | "Should be adapted for no-technical person" (`AGENTS.md:45-50`, goal #2). |

The CLI surfaces do not overlap at the command-API level: `dctl` is a multi-project composition system; ai-agents-sandbox is a four-verb script around a single image. They overlap only on the slice where `dctl` will preset a single agent sandbox.

---

## 4. Config composability

| Axis | `dctl` (planned) | ai-agents-sandbox |
|---|---|---|
| Composition model | Layered manifests; shape being refactored. The premise that authoring composability is required is recorded in [SPEC.md §1.3](./SPEC.md). | None. Monolithic per-image build; agent selection is a single `AGENT=<copilot\|claude\|gemini\|all>` build-arg switching `case` blocks in `image/Containerfile` (`README.md:117-122`). |
| Sub-agent definitions | Not specified at the runtime layer; will be part of the refactor. | Markdown files under `image/agents/<agent>/` are provisioned to `~/.<agent>/agents/` by `image/scripts/entrypoint.sh` (`AGENTS.md:31-33`, `README.md:319-337`). |
| Image-level resource config | Not specified. | `image/.krun_vm.json` (per-image microVM defaults) or `--annotation krun.ram_mib=… --annotation krun.cpus=…` at runtime (`README.md:423-435`, `ai-agents-sandbox.sh:301-302`). |
| Sharing/reuse across sandboxes | Manifest-layer reuse is the intended model ([SPEC.md §1.3](./SPEC.md)). | None. Each agent's slim image is built from the same `Containerfile` under different build-args. |
| Volume model | Per-project workspaces (per [SPEC.md §1.3](./SPEC.md)). | One persistent home volume per agent-flavoured container (`$CTN_NAME-home`); plus the bind-mounted `workspace/` directory (`ai-agents-sandbox.sh:238-247, 289-294`). Single shared home across all projects inside the container. |

**Composability verdict.** `dctl`'s manifest/layer composition model has no analogue in ai-agents-sandbox; conversely, ai-agents-sandbox's "single persistent home across all projects" model has no direct equivalent in `dctl`'s per-project premise ([SPEC.md §1.3](./SPEC.md)). A `dctl` preset that exposes the ai-agents-sandbox UX would need either an explicit shared-home leaf pattern or a per-project volume strategy with separate auth state per project.

---

## 5. Image distribution & per-agent slim builds

Both projects target the OCI registry path (libkrun consumes existing OCI artifacts unchanged via `crun --krun` — [DECISION-LINUX.md §5](./DECISION-LINUX.md)).

ai-agents-sandbox ships a concrete pattern that `dctl` has not yet specified: **per-agent slim builds**. A single `AGENT=<copilot|claude|gemini>` build-arg drives `case` blocks inside `image/Containerfile` to install only the tools that agent needs, producing images named `ai-agents-sandbox-<agent>:latest` (`README.md:117-122`, `README.md:486-498`). Reported sizes (`README.md:131-139`):

| Image | Size |
|---|---|
| `ai-agents-sandbox-copilot` | 588 MB (Copilot CLI installed at runtime after auth) |
| `ai-agents-sandbox-gemini` | 1.76 GB |
| `ai-agents-sandbox-claude` | 1.92 GB |
| `ai-agents-sandbox` (all-in-one) | 2.12 GB |

A `dctl` agent preset can reasonably adopt the same pattern: one `Containerfile`, a single `AGENT` build-arg, and the manifest layer selects which slim image to use.

---

## 6. Maturity & production evidence

Both projects rest on the same upstream — libkrun under the [`containers/`](https://github.com/containers) org (v1.18.0 shipped 2026-04-24 per [RUNTIMES.md §4.4](./RUNTIMES.md)). The same production evidence cited in [DECISION-LINUX.md §2.2](./DECISION-LINUX.md) and [COMPARISON-FLAKE-PILOT.md §5](./COMPARISON-FLAKE-PILOT.md) applies: RamaLama ([Red Hat Developer, Jul 2025](https://developers.redhat.com/articles/2025/07/02/supercharging-ai-isolation-microvms-ramalama-libkrun)), Microsandbox, and krunvm. CVE pipeline runs through standard distro security channels ([DECISION-LINUX.md §2.2](./DECISION-LINUX.md)).

What is project-specific:

- **`dctl`** is planned. The libkrun adapter is milestone T2.0 / T2.1c per [DECISION-LINUX.md §7](./DECISION-LINUX.md) and [SPEC.md §6](./SPEC.md).
- **ai-agents-sandbox** is a working reference of that same stack today. It encodes the preflight (`ai-agents-sandbox.sh:102-156`), the libkrun ≥ 1.18 version gate (`ai-agents-sandbox.sh:45`), the [libkrun#674](https://github.com/containers/libkrun/issues/674) Copilot workaround (`ai-agents-sandbox.sh:259-263`), the resource-annotation form (`ai-agents-sandbox.sh:301-302`), and the macOS Podman-Machine fallback (`ai-agents-sandbox.sh:249-256`).

---

## 7. Overlap analysis & verdict

### 7.1 Same use case at the goal level

Both projects exist to run AI coding agents (Copilot, Gemini, Claude Code) inside a hardened sandbox on Linux. Both keep credentials out of the image and persist them to host-mounted state. Both choose rootless Podman + libkrun + `crun --krun` as the primary runtime when KVM is available. (ai-agents-sandbox pins the guest to openSUSE Tumbleweed per `README.md:1-9`; the `dctl` spec set does not commit to a guest base image.)

### 7.2 Different abstraction level

`dctl` is a **multi-project devcontainer composition system** of which a hardened agent sandbox is one preset ([SPEC.md §1.3](./SPEC.md)). ai-agents-sandbox is a **single-purpose agent runner**: one image (or per-agent slim variant), one container, one persistent home volume, one workspace directory.

### 7.3 Structural subset

ai-agents-sandbox's feature set is expressible inside `dctl` as a single `runtime: { name: krun }` manifest plus a slim image whose `Containerfile` mirrors `image/Containerfile`. The inverse direction — folding `dctl` into ai-agents-sandbox — would require rebuilding the manifest/composition layer that [SPEC.md §1.3](./SPEC.md) commits to, i.e., reconstructing most of what `dctl` is.

The one structural axis that does not map cleanly: ai-agents-sandbox's "single persistent home across all projects" model contradicts `dctl`'s per-project workspace premise ([SPEC.md §1.3](./SPEC.md)). Reconciliation requires either a shared-home leaf pattern in the manifest or accepting a per-project volume model in a `dctl` agent preset.

### 7.4 What `dctl` can adopt from ai-agents-sandbox

The libkrun-adapter milestone in [DECISION-LINUX.md §7](./DECISION-LINUX.md) / [SPEC.md §6](./SPEC.md) has a working reference in ai-agents-sandbox. Items available for adoption, with line citations:

- KVM / libkrun preflight with libkrun ≥ 1.18 version gate (`ai-agents-sandbox.sh:102-156`; `MIN_LIBKRUN_VER` at `ai-agents-sandbox.sh:45`).
- [libkrun#674](https://github.com/containers/libkrun/issues/674) Copilot HTTP/2 vsock workaround (`ai-agents-sandbox.sh:259-263`).
- Resource-limit annotation form (`--annotation krun.ram_mib=…`, `--annotation krun.cpus=…`) and alternative `krun_vm.json` config (`ai-agents-sandbox.sh:301-302`, `README.md:423-435`).
- Per-agent slim-build pattern via `AGENT` build-arg (`image/Containerfile`, `README.md:117-122`, `README.md:486-498`).
- Sub-agent markdown-definition layout: `image/agents/<agent>/` provisioned to `~/.<agent>/agents/` by entrypoint (`AGENTS.md:31-33`).
- macOS Podman-Machine + Hypervisor.framework fallback semantics (`ai-agents-sandbox.sh:249-256`, `README.md:401-417`) — informational only, since `dctl` is Linux-only per [DECISION-LINUX.md §1](./DECISION-LINUX.md).
- Threat-model framing diagrams (`README.md:341-419`) that articulate the microVM attack-path argument compactly for end users.

### 7.5 What ai-agents-sandbox does not currently address

By design, ai-agents-sandbox does not ship:

- Egress allowlist or runtime-agnostic network policy ([SPEC.md §5.2](./SPEC.md) Tier 0).
- Host-side scoped/ephemeral token forwarding ([SPEC.md §5.2](./SPEC.md)) — auth lives inside the container instead.
- Multi-project workspace identity or work-clone-aware container identity ([SPEC.md §1.3](./SPEC.md)).
- Manifest-layer composition or reusable shared layers ([SPEC.md §1.3](./SPEC.md)).
- No-KVM CI parity (`dctl` commits to gVisor for that slot per [DECISION-LINUX.md §3](./DECISION-LINUX.md), [RUNTIMES.md §3.1](./RUNTIMES.md)).

### 7.6 Bottom line

There is no replacement relationship. `dctl` and ai-agents-sandbox share the **runtime/security layer** entirely — same boundary class, same stack, same isolation properties — and overlap on the **product layer** only on the single-sandbox slice that `dctl` will preset. ai-agents-sandbox is the closest available reference implementation of the libkrun adapter [SPEC.md §5.5](./SPEC.md) commits to; its working preflight, version gating, and known-bug workaround are directly portable to that milestone. Once the adapter lands, the ai-agents-sandbox surface is reproducible inside `dctl` as one manifest plus a slim image, at which point the two projects no longer occupy structurally distinct positions for the agent-sandbox use case.

---

## 8. References

### Project-internal

- [DECISION-LINUX.md](./DECISION-LINUX.md) — narrowed runtime decision (Linux).
- [DECISION.md](./DECISION.md) — catalog-level decision (cross-platform).
- [SPEC.md](./SPEC.md) — premises, threat model, tiered migration, adapter sketch.
- [RUNTIMES.md](./RUNTIMES.md) — per-option catalog (§3.1 gVisor, §4.4 libkrun).
- [COMPARISON-FLAKE-PILOT.md](./COMPARISON-FLAKE-PILOT.md) — companion comparison; shares the external-URL set on libkrun, RamaLama, and the runc CVE precedent.

### ai-agents-sandbox

- [val4oss/ai-agents-sandbox](https://github.com/val4oss/ai-agents-sandbox) — upstream repository.
- `README.md` sections cited above: requirements (`:34-85`), runtime usage (`:142-158`), image sizes (`:131-139`), project structure (`:319-337`), security measures + microVM diagram + macOS Hypervisor.framework (`:341-419`), per-agent builds (`:486-498`), persistence (`:443-468`), in-container workflow (`:283-291`).
- `AGENTS.md` mission ordering (`:45-50`), architecture map (`:29-40`).
- `ai-agents-sandbox.sh`: variables (`:32-35`), `MIN_LIBKRUN_VER` (`:45`), `_check_microvm` (`:102-156`), usage (`:163-185`), volume creation (`:238-247`), macOS branch (`:249-256`), libkrun-#674 fallback (`:259-263`), `podman run` arg set (`:289-305`), agent dispatch (`:401-411`).
- `image/Containerfile` (the `AGENT` build-arg switches `case` blocks); `image/agents/<agent>/` (sub-agent markdown definitions); `image/.krun_vm.json` (microVM resource defaults).

### libkrun / `crun --krun` / Podman

- [containers/libkrun](https://github.com/containers/libkrun)
- [containers/libkrun#674 — Copilot HTTP/2 vsock `BufDescTooSmall`](https://github.com/containers/libkrun/issues/674)
- [containers/libkrun commit `757b080b` — vsock fix referenced by `MIN_LIBKRUN_VER`](https://github.com/containers/libkrun/commit/757b080b4c5f5934f8e5320a38b401aaec116764)
- [containers/krunvm](https://github.com/containers/krunvm)
- [crun `krun.1` manpage (openSUSE Tumbleweed)](https://manpages.opensuse.org/Tumbleweed/crun/krun.1.en.html)
- [Red Hat Developer — Supercharging AI isolation: microVMs with RamaLama and libkrun (Jul 2025)](https://developers.redhat.com/articles/2025/07/02/supercharging-ai-isolation-microvms-ramalama-libkrun)
- [podman-network man page (rootless networking, `pasta` / `slirp4netns`)](https://docs.podman.io/en/stable/markdown/podman-network.1.html)

### Shared-kernel CVE precedent (why bare containers are not the boundary)

- [Sysdig — runc container escape vulnerabilities (Nov 2025)](https://www.sysdig.com/blog/runc-container-escape-vulnerabilities) — CVE-2025-31133, CVE-2025-52565, CVE-2025-52881.
- [CNCF — runc container breakout vulnerabilities: a technical overview (Nov 2025)](https://www.cncf.io/blog/2025/11/28/runc-container-breakout-vulnerabilities-a-technical-overview/)
- [emirb — microvm-2026](https://emirb.github.io/blog/microvm-2026/) — hypervisor-escape bug-class economics.

### gVisor (no-KVM CI parity)

- [gvisor.dev — docs](https://gvisor.dev/docs/)
