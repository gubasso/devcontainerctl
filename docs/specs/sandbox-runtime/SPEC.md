# Sandbox Runtime — Security Specification

> Status: Draft
> Scope: Major security re-architecture of `devcontainerctl`'s container/sandbox layer.
> Audience: Maintainers, contributors, and security reviewers.
> Companion: [RUNTIMES.md](./RUNTIMES.md) — full per-option catalog and rejection reasoning.

## 0. Purpose

`devcontainerctl` (`dctl`) exists to provide a **secure, reproducible sandbox** for running AI coding agents (e.g. Claude Code, Codex CLI, Gemini CLI). These agents execute model-generated commands against arbitrary repository content, untrusted dependencies, and remote services; they must be assumed to be running attacker-controlled code at all times.

This document specifies the **podman-first sandbox architecture** for `dctl`:

1. States the project's premises — what the sandbox must achieve and what it must not be (§1).
2. Describes the configured posture (§2).
3. Defines the threat model relevant to AI-agent execution (§3).
4. Names the **viable candidate set** of runtime backends (§4). Full per-option analysis lives in `RUNTIMES.md`.
5. Proposes a tiered build-out plan (§5) keeping the project's ergonomics goals intact (declarative, composable, shareable configuration) while delivering a real security boundary.

The Linux backend is committed in [DECISION-LINUX.md §2](./DECISION-LINUX.md): **libkrun via `crun --krun`, fronted by rootless Podman**. Every container operation in the codebase invokes `podman` and nothing else; `dctl` interprets `devcontainer.json` itself.

---

## 1. Premises

This section is load-bearing for the rest of the spec. Every later decision must be traceable to a premise here, and any deviation must be called out explicitly.

### 1.1 Functional premises (what the sandbox must achieve)

- **Hardware-virtualization boundary against adversarial code.** A serious attempt at host compromise must require a hypervisor-class bug, not a routine syscall trick or a known kernel CVE. Anything weaker than a KVM-class boundary (or platform-equivalent: Apple Virtualization.framework) is unacceptable as the *primary* isolation, regardless of how cleanly it integrates.
- **Cross-platform.** Linux is the primary target (openSUSE in particular, given the project's image base). macOS is a first-class secondary target. Windows is best-effort via WSL2.
- **OCI-image-driven authoring surface.** The existing `images/` Containerfile flow and `devcontainer.json` schema are the user-authoring surface. The runtime swap may convert OCI images into other formats internally (rootfs tarballs, ext4, etc.); the user never authors anything other than OCI/devcontainer artifacts.
- **Acceptable cold-start.** A few hundred milliseconds to a few seconds for `dctl ws up`. Sub-second is preferred; multi-second is the upper bound for laptop ergonomics.

### 1.2 Security goals

- The host kernel **must not** be reachable from agent-executed code through anything weaker than a hypercall + KVM (or HVF) boundary.
- A single container/runtime/kernel CVE **must not** be a host-compromise event by itself.
- Long-lived OAuth tokens (`gh`, `glab`, Claude session) **must not** be live-mounted into the agent. Forwarding is short-lived, scoped, and ephemeral.
- Default container egress **must** be allowlisted to model APIs, package mirrors, and the user's git remotes; everything else is denied by default.
- The host `/tmp` **must not** be bind-mounted into the agent container.
- `no-new-privileges` and `--cap-drop=ALL` are present in the agents layer's default `runArgs`.

### 1.3 End-user ergonomics premises

- The user-facing schema (`devcontainer.json`, manifest layers, leaf-project overrides) is **runtime-agnostic**. It does not name a runtime.
- Runtime selection composes through the same precedence as other config keys: leaf-project pin → user default → env / flag override.
- The runtime adapter is the **only** place runtime-specific code lives. `lib/dctl/runtime/<name>.sh` modules implement a small interface (`rt_run`, `rt_exec`, `rt_ps`, `rt_rm`, `rt_build`); everything else in `lib/dctl/` stays runtime-agnostic.
- Workflows must remain **simple, declarative, composable, and shareable** across machines and teams. Projects must be able to pin a runtime via a manifest field; users must be able to set a global default; both must be overridable.
- We are willing to **implement parts of the build/run plumbing ourselves** if that buys a stronger security boundary — provided the implementation is bounded in scope and the user-facing surface remains declarative. See `RUNTIMES.md` §4.1 for the bare-Firecracker cost estimate (~3–5 weeks one-time + ongoing maintenance).

### 1.4 Anti-premises (what we explicitly reject)

- **Bare Podman (rootful or rootless) as the primary boundary.** See §1.5 for reasoning. Hardened seccomp, AppArmor, and `cap-drop` are defense-in-depth, not the boundary.
- **`--privileged`, container-socket bind-mount, `--cap-add` for non-essential caps.** Disallowed across all configurations.
- **A runtime that requires re-implementing the OCI ecosystem from scratch** with a permanent maintenance burden the size of containerd. Targeted plumbing (rootfs builder, in-guest init, vsock channel) is acceptable; rebuilding containerd is not.
- **Hardware-attested isolation against the host (Confidential Containers / TDX / SEV-SNP)** as the threat-model framing. The host is trusted; the workload is not. We solve workload isolation, not host distrust.
- **Language-level sandboxes** (V8 isolates, WebAssembly) as the boundary. Cannot host the agent's full toolchain (`pytest`, `cargo`, `git`, native compilers).
- **CI-only / cluster-only runtimes** (firecracker-containerd, flintlock, AWS Nomad FC driver) as the laptop default. Useful as components; wrong shape for a per-developer CLI.
- **Larger-TCB hypervisors when a smaller-TCB one is available.** QEMU full-fat is rejected as the laptop default for this reason; see `RUNTIMES.md` §4.5.

### 1.5 Why bare containers are insufficient (the reasoning behind §1.4)

The shared-kernel container model is a resource-isolation boundary, not a security boundary. Three observations make it unacceptable as the primary boundary for the AI-agent threat model:

1. **Recurring container breakouts.** November 2025 alone produced **three back-to-back runc CVEs** — CVE-2025-31133, CVE-2025-52565, CVE-2025-52881 — each delivering full container breakout via mount races and procfs symlink tricks. These affect **Podman, Kubernetes, and every other runc-based runtime alike**. See [Sysdig analysis](https://www.sysdig.com/blog/runc-container-escape-vulnerabilities) and [CNCF technical overview](https://www.cncf.io/blog/2025/11/28/runc-container-breakout-vulnerabilities-a-technical-overview/).
2. **Kernel LPE cadence.** Linux kernel local-privilege-escalation surfaces at roughly monthly cadence (bpf, io_uring, netfilter, page-cache aging, and so on). Each one is a host compromise on shared-kernel runtimes. Hypervisor escapes, by contrast, are a $250K–$500K bug class ([emirb microvm-2026](https://emirb.github.io/blog/microvm-2026/)).
3. **Namespaces are a resource-control mechanism, not a security boundary.** This is a design fact, not a bug. Namespaces let the kernel partition resources for non-malicious tenants; they do not constitute a barrier against an adversary running code on the same kernel.

Rootless mode reduces *blast radius* (escape lands as the invoking user instead of host root) but does not change the *probability*: every kernel LPE still lands on the host. The November 2025 runc CVEs explicitly affect rootless Podman. Rootless Podman remains valuable as a **controller around** a microVM (see `RUNTIMES.md` §4.4 for libkrun + `crun --krun`); it is not the boundary.

---

## 2. Configured posture (target)

`dctl` is a Bash CLI that consumes `devcontainer.json` directly and composes layers via YAML manifests (`schemas/compose.schema.yaml`). Every container operation invokes `podman` and nothing else; `lib/dctl/lifecycle.sh` interprets the `devcontainer.json` lifecycle keys (`postCreateCommand`, `postStartCommand`, `remoteEnv`, `mounts`, `runArgs`) in-process. Implementation phasing is in [IMPLEMENTATION-PLAN.md](./IMPLEMENTATION-PLAN.md).

### 2.1 Required posture

The composed `devcontainer.json` (base + agents leaf) **must** satisfy all of the following:

- **Not privileged.** No `privileged: true`, no container-socket bind-mount, no `--cap-add`. Audited via `grep -rn "privileged|cap-add|userns"` returning zero hits.
- **Runs as a non-root user.** `images/agents/Containerfile` creates `$USERNAME` with UID/GID matched to the host at build time; `base/devcontainer.json` sets `remoteUser`. The container is non-root from PID 1 onward.
- **Sudo is narrowed.** Passwordless `sudo /usr/bin/zypper` only; no `NOPASSWD: ALL`. Defense-in-depth — a crafted local package with a `%post` script can still gain root inside the container, which is acceptable because the surrounding boundary is a microVM, not the host kernel.
- **Default seccomp is the strict baseline** under microVM isolation ([§5.4 Tier 3](#54-tier-3--relax-inner-constraints-once-the-outer-boundary-is-a-hypervisor)). The permissive `seccomp-bwrap.json` profile is retained only for the `agents-permissive` opt-in profile that hosts Codex CLI's inner `bwrap` sandbox.
- **AppArmor stays enabled** for the default `agents-strict` profile; `apparmor=unconfined` is only acceptable on the opt-in `agents-permissive` profile.
- **`--cap-drop=ALL` and `--security-opt=no-new-privileges`** appear in the agents layer's default `runArgs`.
- **No long-lived OAuth token directories are bind-mounted.** `~/.config/gh`, `~/.config/glab-cli`, `~/.claude*`, `~/.codex`, `~/.gemini` are **never** bind-mounted live; tokens are forwarded as short-lived env (`GH_TOKEN`, `GITLAB_TOKEN`) or copied into a per-session ephemeral tmpdir under `$DCTL_CACHE_DIR/sessions/<workspace-hash>/`. See [§5.1 Tier 0](#51-tier-0--configuration-hygiene-do-now-regardless-of-runtime) and [IMPLEMENTATION-PLAN.md §Phase 4](./IMPLEMENTATION-PLAN.md).
- **`/tmp` is a tmpfs**, never a host bind.
- **Network egress is allowlisted by default.** A `lib/dctl/net.sh` module emits the in-VM nftables ruleset; only model APIs, package mirrors, and the workspace's git remotes are reachable.
- **Per-workspace container identity.** Every container carries `--label devcontainer.local_folder=$PWD`; `dctl ws` queries match on that label, so work-clones of the same repo produce distinct containers.

---

## 3. Threat Model

The workload is **AI agents executing model-generated commands**. Every command must be treated as if it originated from prompt injection through scraped documentation, dependency READMEs, untrusted MCP tool output, or `npm install` post-install scripts.

The realistic attack tree, in order of frequency and skill required:

### 3.1 Token exfiltration without escape (highest frequency, lowest skill)

The agent reads `~/.config/gh/hosts.yml`, `~/.claude/.credentials.json`, `$GH_TOKEN` env, `$GITLAB_TOKEN` env — all mounted/injected by design — and POSTs them to an attacker-controlled URL via the open egress.

**This works today and is unrelated to the container boundary. No escape is required.** Switching the runtime does not address this.

### 3.2 Host filesystem reach via configured mounts

`/tmp` host bind, `~/.gitconfig` (RO but reveals identity), the coordinator layer's RO `~/Projects` mount. None of these are escapes — they are configured access surfaces that the threat model must treat as adversarially read.

### 3.3 Container → host privilege escalation

Requires either an OCI runtime (runc / crun) bug or a kernel LPE.

- **November 2025** brought three back-to-back runc CVEs (CVE-2025-31133, CVE-2025-52565, CVE-2025-52881), each delivering full container breakout via mount races and procfs symlink tricks. These affect **Podman, Kubernetes, and every other runc-based runtime alike**.
- **Continuous background:** a steady stream of bpf / io_uring / netfilter / page-cache LPEs in the upstream kernel.

This is the class of risk that shared-kernel container runtimes cannot structurally eliminate. *Namespaces are a resource-control mechanism, not a security boundary.*

### 3.4 Lateral abuse of the agent's footprint (no escape required)

Even without a kernel or runtime bug:

- Write malicious `pre-commit` hooks (the project deliberately runs `pre-commit install` in `postCreateCommand`, which makes this path attractive).
- Modify shell rc files in the persisted `~/.claude` directory.
- Drop a binary in `/tmp` that survives a container restart via the host bind mount.
- Poison `.git/config` or `.gitignore` to leak files on next commit.

### 3.5 Implications

- **(3.1)** is the most under-mitigated risk today and is **not** addressed by any runtime swap. It is a configuration and policy problem (Tier 0 in §5.1).
- **(3.3)** is the risk that requires a stronger boundary. For this risk class, only a hardware-virtualization boundary qualitatively changes the picture; every kernel LPE and runc CVE keeps applying as long as the kernel is shared.
- **(3.2)** and **(3.4)** are addressed primarily by tightening mount and persistence policies, independent of runtime choice.

---

## 4. Candidate Set

The viable backends fall into three categories. **No single default is chosen in this revision** — selection is deferred to a prototyping milestone (§4.4). Per-option analysis (security posture, OCI fit, maintenance, what `dctl` would own, verdict) is in `RUNTIMES.md`; this section is the index.

### 4.1 Hardware-virt microVM candidates (primary)

All four candidates provide a KVM-class hypervisor boundary. They are FC-class or FC-equivalent on the security axis; they differ on plumbing cost, OCI integration, and operational friction.

| Candidate | One-line characterization | Reference |
|---|---|---|
| **Bare Firecracker** with a `dctl`-owned controller | Smallest TCB, highest implementation cost (~3–5 wk one-time + ongoing rootfs/kernel maintenance). High-assurance escape hatch. | `RUNTIMES.md` §4.1 |
| **Kata Containers + Firecracker** | OCI-native via containerd; Kata-on-FC is second-class within Kata (no virtio-fs, devmapper snapshotter required). | `RUNTIMES.md` §4.2 |
| **Kata Containers + Cloud Hypervisor** | Same KVM boundary class as FC, slightly larger device surface in default config; virtio-fs available; the path the Kata community actively exercises. | `RUNTIMES.md` §4.3 |
| **libkrun + `crun --krun`** on Podman-rootless | Rust VMM derived from FC and CH; same hardware-isolation class; lowest plumbing cost (`podman --runtime krun run` consumes OCI images directly). | `RUNTIMES.md` §4.4 |

**Residual host-kernel surface under a hardware-virt boundary.** A hardware-virt boundary **shifts** the host-kernel attack surface; it does not reduce it to zero. Every KVM-based VMM retains two well-defined host-facing surfaces: (a) `/dev/kvm` ioctls (the hypercall path), and (b) the VMM's virtio device backends (block, net, vsock, fs, optionally gpu). This is a different category from the shared-kernel case — a compromise here is a hypervisor- or virtio-class bug ($250K–$500K bounty class per [emirb microvm-2026](https://emirb.github.io/blog/microvm-2026/)), not a routine kernel LPE or syscall trick — but it is not the empty set. Recent precedent: [CVE-2026-5747](https://aws.amazon.com/security/security-bulletins/2026-015-aws/) (Firecracker virtio-pci OOB write, opt-in flag) shows that "small VMM" is not "no VMM CVEs."

The size and shape of (b) varies between the §4.1 candidates and is an operational trade-off rather than a boundary-class difference:

- **Firecracker** ships the smallest device set by design: virtio-net, virtio-blk, serial, no virtio-fs, no virtio-gpu. Kata-on-FC is forced into the devmapper snapshotter for the same reason.
- **Cloud Hypervisor** adds virtio-fs, virtio-mem, PCI hotplug, VFIO, GPU passthrough (Landlock-sandboxed host-side; see `RUNTIMES.md` §4.3).
- **libkrun** uses virtio-fs as the default rootfs path (how `crun --krun` mounts the OCI bundle), and its TSI feature (Transparent Socket Impersonation) terminates per-connection TCP state on the **host's** TCP/IP stack via a userspace proxy in the VMM process — different from Firecracker's TAP/bridge path, neither strictly smaller. virtio-gpu (virgl/venus) is available via `krun_set_gpu_options` but **off by default** in the Podman+krun path; enabling it would meaningfully widen the host-side surface and is therefore gated behind an explicit profile opt-in.

The colleague-style critique "krun shares the kernel with the host" conflates (b) with shared-kernel namespacing and is **wrong on the boundary class** — the guest runs its own kernel (`init.krun` as guest PID 1; `libkrunfw` bundles it), runc-class breakouts do not reach the host, and kernel LPEs inside the guest stay inside the guest. But the underlying intuition (libkrun's host-side device-backend surface is non-zero and **wider** than bare Firecracker's) is correct and is accepted as the trade-off in `DECISION-LINUX.md` §2.4 and §6 Risk #1. The bare-Firecracker escape hatch in `RUNTIMES.md` §4.1 / `DECISION-LINUX.md` §2.5 remains documented for cases where minimizing this surface is worth the plumbing cost.

### 4.2 Platform-specific candidate

- **Apple `container`** — the macOS-native equivalent of an FC-class microVM via Virtualization.framework. Pairs with any of the §4.1 options on the Linux side. See `RUNTIMES.md` §4.6.

### 4.3 Fallback

- **gVisor (`runsc`)** — userspace-kernel sandbox. Documented fallback for environments without KVM (CI runners, cloud VMs without nested virt). Not a replacement for hardware isolation. See `RUNTIMES.md` §3.1.

### 4.4 Selection criteria

The final pick should be made on, in priority order:

1. **Security.** Boundary class (hypervisor vs userspace-kernel vs shared-kernel), TCB size, CVE history, supply-chain trust. All §4.1 candidates clear the bar; tie-breakers below.
2. **Operational simplicity for the user.** Cold-start, mount UX, devcontainer feature parity, error messages.
3. **What `dctl` must own.** Adapter glue is fine; rootfs builders, kernel-image lifecycle, in-guest agents, and containerd shims are real ongoing costs and must be budgeted explicitly.
4. **Cross-platform parity.** A single mental model across Linux and macOS is preferred over two unrelated backends.

A prototyping milestone should produce concrete numbers (cold-start, mount latency, smoke-test pass rate, devcontainer-feature parity) for at least two §4.1 candidates before committing to a default.

### 4.5 What is explicitly *not* in the candidate set

The following options were evaluated and rejected. Reasoning is in `RUNTIMES.md`; pointers here:

- Bare Podman (rootful) — `RUNTIMES.md` §1.1
- Hardened-container path alone — `RUNTIMES.md` §1.2
- Podman rootless as the boundary — `RUNTIMES.md` §2.1 (kept as defense-in-depth and as a controller front-end for libkrun)
- bubblewrap / Landlock / seccomp-only as the boundary — `RUNTIMES.md` §2.3
- QEMU full-fat — `RUNTIMES.md` §4.5 (rejected on TCB grounds)
- firecracker-containerd, flintlock, Ignite, AWS Nomad FC driver — cluster-shaped, see `RUNTIMES.md` §5.1–§5.3, §5.9
- SUSE flake-pilot — `RUNTIMES.md` §5.4 (inspirational only)
- Hyperlight — `RUNTIMES.md` §5.5 (cannot host the agent toolchain)
- Confidential Containers — `RUNTIMES.md` §5.6 (wrong threat model)
- V8 isolates / WebAssembly — `RUNTIMES.md` §5.7
- youki without an FC integration — `RUNTIMES.md` §5.8

---

## 5. Migration Tiers

### 5.1 Tier 0 — Configuration hygiene (do now, regardless of runtime)

These are cheap and address the realistic attack tree (§3.1, §3.4) more effectively than any runtime change.

1. **Stop bind-mounting full token directories.** Replace `~/.config/gh` and `~/.config/glab-cli` mounts (`devcontainers/base/devcontainer.json:17-26`) and the `~/.claude*` mounts (`devcontainers/agents/devcontainer.json:113-122`) with **scoped, ephemeral token forwarding**. The `gh auth token` extraction in `lib/dctl/auth.sh:30` is the right model — extend it: the agent should never see the OAuth refresh token, only a short-lived `GH_TOKEN`. Same for Claude.
2. **Drop the host `/tmp` bind** (`devcontainers/base/devcontainer.json:27-30`). Use a per-container `tmpfs`. There is no good reason an AI agent's `/tmp` should be the host's `/tmp`.
3. **Egress allowlist by default.** A `dctl`-managed `iptables`/`nftables` rule (or a userspace proxy) restricting outbound to model APIs (`api.anthropic.com`, `api.openai.com`, `*.googleapis.com`), the package mirrors actually used, and the user's git remotes. This single change defangs the most common exfiltration scenario.
4. **Add `no-new-privileges` and `--cap-drop=ALL`** to `runArgs` in the agents layer. The seccomp profile is permissive on syscalls; cap-drop covers the rest of the historical privilege paths.
5. **Document the `bwrap`/AppArmor trade-off as a named profile.** Ship `agents-permissive` (current `bwrap`-friendly behavior) alongside `agents-strict` (moby default seccomp + AppArmor enabled) for projects that don't need Codex's `bwrap` inner sandbox. Make the choice explicit and opt-in.

### 5.2 Tier 1 — Runtime adapter on top of Podman-rootless

This is the cheap correctness win and the engineering precondition for Tier 2.

1. Introduce `DCTL_RUNTIME ∈ {podman, kata-fc, kata-ch, krun, gvisor, apple-container}` and route every container operation in `lib/dctl/ws.sh` through a small adapter (`lib/dctl/runtime/<name>.sh`). The user-facing schema (`devcontainer.json`, manifests) does not change. The `podman` adapter calls `podman` directly — there is no other container CLI in the codebase.
2. Configure Podman-rootless defaults (no privileged ports, pasta networking, `userns=auto:size=65536`). Podman-rootless is treated as **defense-in-depth and a controller front-end** for §5.3, not as the security boundary.
3. Make `dctl test` runtime-aware: the same smoke-test must pass against every backend.

### 5.3 Tier 2 — FC-class hardware boundary as the recommended default (Linux + macOS)

This delivers the real hardware boundary without breaking ergonomics. Because all §4.1 candidates consume OCI images, `images/` and the Containerfile build flow do not change at this tier.

1. Add at least one §4.1 candidate as a backend behind the same adapter introduced in Tier 1. The specific candidate (Kata-FC, Kata-CH, libkrun, or bare-FC) is chosen based on Tier 1 prototyping results and the §4.4 criteria.
2. Add **Apple `container`** as the macOS backend.
3. Add **gVisor** as the no-KVM fallback for CI and similar environments.
4. The composition layer gains a new layer kind: `runtime-policy` (e.g. `runtime: kata-ch`, `egress: allowlist`, `mounts: scoped`). Leaf-layer ergonomics remain unchanged for most users.

### 5.4 Tier 3 — Relax inner constraints once the outer boundary is a hypervisor

Once an FC-class runtime is the default, the inner-container freedom can be expanded confidently (package installs, nested container runtimes, build sandboxes) because the boundary is now a hypervisor rather than a syscall filter. The custom permissive seccomp profile (`devcontainers/agents/seccomp-bwrap.json`) becomes non-load-bearing and `agents-strict` can become the default profile under VM-bounded runtimes.

### 5.5 Runtime-abstraction layer (sketch)

```
lib/dctl/
  runtime/
    common.sh        # interface: rt_run, rt_exec, rt_ps, rt_rm, rt_build
    podman.sh        # podman-rootless, pasta, userns=auto
    kata-fc.sh       # nerdctl --runtime io.containerd.kata.v2 with FC VMM config
    kata-ch.sh       # nerdctl --runtime io.containerd.kata.v2 with CH VMM config
    krun.sh          # podman --runtime krun ...
    bare-fc.sh       # dctl-owned FC controller (escape hatch)
    gvisor.sh        # nerdctl --runtime runsc ...
    apple.sh         # `container run …`
  ws.sh              # calls rt_* via the adapter
  image.sh           # calls rt_build via the adapter
```

Runtime selection mirrors how config already composes:

1. Project leaf layer pins `runtime: kata-ch` (or any other supported value).
2. User global default in `~/.config/dctl/default/devcontainer.json` sets the user's preferred runtime.
3. `DCTL_RUNTIME` env or `--runtime` flag overrides for one-off cases.

Composable, declarative, runtime-agnostic. The same `python.yaml` manifest produces a gVisor-sandboxed container on a CI machine without nested virt and an FC-class microVM on a KVM-equipped laptop.

---

## 6. Migration Sketch

| Step | Files touched | Effort | Risk |
|---|---|---|---|
| T0.1 — token forwarding instead of mounts | `lib/dctl/auth.sh`, `devcontainers/base/devcontainer.json:17-26`, `devcontainers/agents/devcontainer.json:112-133` | 1–2 d | Low (gh exists; Claude needs session-token forwarding equivalent) |
| T0.2 — drop host `/tmp` bind, switch to tmpfs | `devcontainers/base/devcontainer.json:27-30` | 1 h | Low |
| T0.3 — egress allowlist | new `lib/dctl/net.sh` + `nftables` shim or `slirp4netns --enable-sandbox --disable-host-loopback` | 3–5 d | Medium (UX for adding domains) |
| T0.4 — `no-new-privileges`, `cap-drop=ALL` | `devcontainers/agents/devcontainer.json:107-111` | 30 min | Low (verify Codex `bwrap` still starts) |
| T0.5 — `agents-strict` profile alongside `agents-permissive` | new `devcontainers/agents-strict/` | 1 d | Low |
| T1.1 — runtime adapter | `bin/dctl`, `lib/dctl/ws.sh`, new `lib/dctl/runtime/*.sh` | 2–3 d | Low; podman-first throughout |
| T1.2 — Podman rootless backend + smoke tests | `lib/dctl/runtime/podman.sh`, `tests/` | 2 d | Medium (slirp4netns/pasta perf) |
| T2.0 — prototyping milestone (§4.4) | one-off; produce numbers for at least two §4.1 candidates | 1–2 wk | Low (information-gathering) |
| T2.1a — Kata-FC backend | `lib/dctl/runtime/kata-fc.sh`, docs, devmapper setup | 3–5 d | Medium (host KVM detection, runtime class registration in containerd, devmapper) |
| T2.1b — Kata-CH backend | `lib/dctl/runtime/kata-ch.sh`, docs | 3–5 d | Medium (host KVM detection, runtime class registration) |
| T2.1c — libkrun backend | `lib/dctl/runtime/krun.sh`, docs | 1–2 d | Low–Medium (relies on Podman-rootless from T1.2) |
| T2.1d — bare Firecracker backend (escape hatch) | `lib/dctl/runtime/bare-fc.sh`, rootfs builder, in-guest init, vsock helper | 3–5 wk | High (largest scope; deferred unless required) |
| T2.2 — Apple `container` backend (macOS) | `lib/dctl/runtime/apple.sh` | 3–5 d | Medium (macOS 26+ only) |
| T2.3 — gVisor backend (no-KVM environments) | `lib/dctl/runtime/gvisor.sh` | 2 d | Low–Medium (syscall-compat surprises) |
| T2.4 — `runtime:` field in manifest schema | `schemas/compose.schema.yaml`, `lib/dctl/init.sh` | 1 d | Low |

Tier 0 + Tier 1 ship independently of the §4.1 selection. Tier 2 begins with the prototyping milestone (T2.0); the actual T2.1 backend chosen as default falls out of those numbers.

---

## 7. Acceptance Criteria

A future revision of this spec is considered to have **reached** each tier when:

### Tier 0
- No long-lived OAuth token files are bind-mounted into agent containers.
- Host `/tmp` is no longer bind-mounted.
- Default container egress is restricted to an explicit allowlist; users can extend the allowlist via declarative config.
- `no-new-privileges` and `--cap-drop=ALL` are present in the agents layer's default `runArgs`.
- `agents-strict` and `agents-permissive` profiles both exist and are documented.

### Tier 1
- `dctl` command paths route through the runtime adapter; no direct container-CLI shell-out remains in `lib/dctl/` outside the adapter.
- Podman rootless is a fully tested backend; the standard smoke-test passes against it.
- `DCTL_RUNTIME`, project-level, and user-level runtime selection all work.

### Tier 2
- The prototyping milestone (T2.0) has produced concrete numbers for at least two §4.1 candidates.
- The chosen FC-class backend is documented as the recommended default for AI-agent workloads on KVM-capable Linux.
- `apple-container` (macOS) backend passes the same smoke-test.
- `gvisor` is available for no-KVM environments.
- The manifest schema supports a `runtime:` field; runtime selection composes through the layer system with the same precedence rules as other config keys.

### Tier 3
- The custom permissive seccomp profile is no longer required by default; `agents-strict` becomes the default profile under VM-bounded runtimes.
- Inner nested container runtimes (e.g. nested Podman) and package installation work without weakening the host's security posture.

---

## 8. Open Questions

- **Final §4.1 backend choice.** What are the cold-start, mount-latency, devcontainer-feature-parity, and smoke-test numbers for at least two of {bare Firecracker, Kata+FC, Kata+CH, libkrun} on the developer-laptop reference hardware? Selection criteria are defined in §4.4.
- **Cross-platform mental model.** Does libkrun's macOS HVF backend reach feature parity with Apple `container`, or do we keep two backends on macOS?
- **Claude session token forwarding.** Is there a documented short-lived token export path for Claude Code, equivalent to `gh auth token`? If not, what is the minimal subset of `~/.claude` that must be projected into the container, and can it be projected as an ephemeral copy rather than a live mount?
- **Egress allowlist UX.** How should users add domains? Static manifest entries, an interactive `dctl net allow <host>` command, or both? What is the right default set?
- **CI parity.** Some CI environments lack nested virtualization. The default backend in CI must be either rootless containers + gVisor, or rootless containers with the strict profile. The spec should pick one as the documented CI default.
- **Image distribution.** Kata consumes OCI images, but rootfs construction has subtle differences (init systems, kernel modules, agent injection). Are upstream `images/agents/Containerfile` artifacts directly compatible, or is a Kata-specific (or libkrun-specific) build target needed?
- **Cross-runtime feature parity.** Some `devcontainer.json` features (e.g. `mounts`, `forwardPorts`, lifecycle scripts) may behave differently across backends. The runtime adapter must define which subset is portable; the rest must produce a clear error rather than silently degrade.

---

## 9. References

### Runtimes and VMMs
- [Firecracker — homepage](https://firecracker-microvm.github.io/)
- [Firecracker — design.md](https://github.com/firecracker-microvm/firecracker/blob/main/docs/design.md)
- [Firecracker — repository](https://github.com/firecracker-microvm/firecracker)
- [AWS — Announcing Firecracker (open-source)](https://aws.amazon.com/blogs/opensource/firecracker-open-source-secure-fast-microvm-serverless/)
- [Microarchitectural Security of AWS Firecracker VMM (arXiv:2311.15999)](https://arxiv.org/pdf/2311.15999)
- [Kata Containers — homepage](https://katacontainers.io/)
- [Kata Containers — releases](https://github.com/kata-containers/kata-containers/releases)
- [Kata Containers — PTG October 2025](https://katacontainers.io/blog/kata-community-ptg-updates-october-2025/)
- [Kata + Firecracker how-to](https://github.com/kata-containers/kata-containers/blob/main/docs/how-to/how-to-use-kata-containers-with-firecracker.md)
- [Cloud Hypervisor — repository](https://github.com/cloud-hypervisor/cloud-hypervisor)
- [Cloud Hypervisor — Landlock docs](https://github.com/cloud-hypervisor/cloud-hypervisor/blob/main/docs/landlock.md)
- [Cloud Hypervisor — release notes](https://github.com/cloud-hypervisor/cloud-hypervisor/blob/main/release-notes.md)
- [containers/libkrun](https://github.com/containers/libkrun)
- [libkrun #538 — security model discussion](https://github.com/containers/libkrun/discussions/538)
- [containers/krunvm](https://github.com/containers/krunvm)
- [Red Hat Developer — RamaLama + libkrun (Jul 2025)](https://developers.redhat.com/articles/2025/07/02/supercharging-ai-isolation-microvms-ramalama-libkrun)
- [firecracker-containerd — snapshotter docs](https://github.com/firecracker-microvm/firecracker-containerd/blob/main/docs/snapshotter.md)
- [flintlock — repository](https://github.com/liquidmetal-dev/flintlock)
- [Ignite — repository (archived)](https://github.com/weaveworks/ignite)
- [firecracker-go-sdk](https://github.com/firecracker-microvm/firecracker-go-sdk)
- [firepilot — Rust FC SDK](https://github.com/rik-org/firepilot)
- [firectl](https://github.com/firecracker-microvm/firectl)
- [iximiuz Labs — Firecracker hands-on](https://labs.iximiuz.com/courses/firecracker-hands-on/run-first-microvm)
- [Single-app rootfs for Firecracker (cloudkernels.net)](https://blog.cloudkernels.net/posts/fc-rootfs/)
- [buildfs (crates.io)](https://crates.io/crates/buildfs)
- [Hyperlight — Microsoft introduction (Nov 2024)](https://opensource.microsoft.com/blog/2024/11/07/introducing-hyperlight-virtual-machine-based-security-for-functions-at-scale/)
- [OSInside/flake-pilot](https://github.com/OSInside/flake-pilot)
- [SUSE Package Hub — flake-pilot](https://packagehub.suse.com/packages/flake-pilot/)

### Podman security
- [Podman — rootless tutorial](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md)
- [Red Hat — Rootless Podman user-namespace modes](https://www.redhat.com/en/blog/rootless-podman-user-namespace-modes)

### gVisor and macOS
- [gVisor — docs](https://gvisor.dev/docs/)
- [gVisor — performance guide](https://gvisor.dev/docs/architecture_guide/performance/)
- [Apple — `container` repository](https://github.com/apple/container)
- [InfoQ — Apple Containerization: native Linux container support for macOS](https://www.infoq.com/news/2025/06/apple-container-linux/)
- [The Register — Apple Containerization](https://www.theregister.com/2025/06/10/apple_tries_to_contain_itself/)

### Vulnerabilities and analyses
- [Sysdig — runc CVE-2025-31133, -52565, -52881 analysis](https://www.sysdig.com/blog/runc-container-escape-vulnerabilities)
- [CNCF — runc container breakout vulnerabilities, technical overview](https://www.cncf.io/blog/2025/11/28/runc-container-breakout-vulnerabilities-a-technical-overview/)
- [GHSA — CVE-2025-31133 advisory](https://github.com/advisories/GHSA-9493-h29p-rfm2)
- [GHSA — CVE-2025-52881 advisory](https://github.com/advisories/GHSA-cgrx-mc8f-2prm)
- [stack.watch — Firecracker CVEs](https://stack.watch/product/amazon/firecracker/)
- [emirb — Your Container Is Not a Sandbox: The State of MicroVM Isolation in 2026](https://emirb.github.io/blog/microvm-2026/)
- [Northflank — Best AI code-execution sandbox in 2026](https://northflank.com/blog/best-code-execution-sandbox-for-ai-agents)
- [Northflank — Kata vs Firecracker vs gVisor](https://northflank.com/blog/kata-containers-vs-firecracker-vs-gvisor)
- [Northflank — Firecracker vs QEMU](https://northflank.com/blog/firecracker-vs-qemu)
- [AWS — Enhancing Kubernetes workload isolation with Kata](https://aws.amazon.com/blogs/containers/enhancing-kubernetes-workload-isolation-and-security-using-kata-containers/)
