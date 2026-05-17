# Sandbox Runtime — Linux Implementation Decision

> Status: Decided
> Decision date: 2026-05-11
> Scope: Linux implementation of the sandbox runtime backend for `devcontainerctl` (`dctl`). Selects the single backend to build.
> Companions: [SPEC.md](./SPEC.md), [RUNTIMES.md](./RUNTIMES.md), [DECISION.md](./DECISION.md) (broader catalog-level decision, retained for reference).
> Relationship to [DECISION.md](./DECISION.md): this document **narrows** the catalog-level decision to the single shippable backend for this implementation and excludes the cross-platform, escape-hatch, and contingency-adapter slots called out there. DECISION.md remains valid as the catalog view; this document is the implementation contract.

## 0. Summary

This implementation ships **one** working Linux solution and **one** CI-only fallback for environments without KVM.

- **Primary backend:** **libkrun via `crun --krun`, fronted by Podman-rootless.**
- **No-KVM CI fallback:** **gVisor (`runsc`).** Documented as fallback only; not a second supported backend on developer workstations.

| Slot | Pick | One-line rationale |
|---|---|---|
| Primary (Linux, KVM available) | **libkrun + `crun --krun`** | KVM-class boundary, OCI-native, smallest adapter footprint among hardware-virt candidates; production-proven via RamaLama / Microsandbox / krunvm. |
| Fallback (CI runners without KVM) | **gVisor** | Userspace-kernel sandbox; the only viable answer for CI runners and cloud VMs without nested virtualization. |

**Out of scope for this implementation (intentional).** macOS, Apple `container`, bare Firecracker, Kata-Firecracker, Kata-Cloud-Hypervisor, libkrun-on-HVF. These remain catalog items in [DECISION.md](./DECISION.md) and [RUNTIMES.md](./RUNTIMES.md) but are not built here.

This decision intentionally keeps **one** runtime adapter built and tested in this implementation. Catalog adapters can be added behind the same interface ([SPEC.md §5.5](./SPEC.md)) in subsequent iterations without breaking the user-facing surface.

---

## 1. Decision criteria

In priority order:

1. **Security is the primary goal.** The sandbox exists to run LLM agents that may execute attacker-controlled or model-generated instructions. A **KVM-class hardware-virtualization boundary** — separate guest kernel, no shared-kernel namespace boundary — is the hard requirement. The November 2025 runc CVE cluster ([Sysdig — runc container escape vulnerabilities](https://www.sysdig.com/blog/runc-container-escape-vulnerabilities), [CNCF — runc breakout technical overview](https://www.cncf.io/blog/2025/11/28/runc-container-breakout-vulnerabilities-a-technical-overview/)) is the reference precedent: shared-kernel containers are not a sufficient boundary for this threat model.
2. **Production-proven and well-maintained.** Active upstream, real production users, stable cadence, healthy CVE-response track record.
3. **Enables clean UX.** Simple commands, declarative + composable + shareable manifests. The amount of plumbing `dctl` itself has to own is the dominant UX cost.
4. **Single working Linux implementation.** This ships **one** solution that works fully on Linux. Multi-platform parity, escape hatches, and alternative backends are deferred.
5. **Migration is cheap.** A future Rust rewrite or full refactor is acceptable; do not over-weight switching cost when picking now.

Explicitly **not** criteria:

- **Editor / IDE integration.** Compatibility with VS Code Remote-Containers, GitHub Codespaces, or the `devcontainer up` CLI is **a side-effect** of preserving the OCI/devcontainer authoring schema, never a requirement. The product goal of this runtime is **sandboxing LLM agents**; if `devcontainer.json` compatibility happens to keep working as a downstream consequence, that is welcome but does not drive the runtime choice.
- **macOS support.** Out of scope here. Tracked in [DECISION.md §3](./DECISION.md) for future consideration.
- **Multi-backend catalog at runtime.** This implementation ships one backend value plus the documented CI fallback; alternatives remain catalog-only.

The §1.1 hardware-virt premise from [SPEC.md](./SPEC.md) (KVM-class boundary, no shared kernel) is a precondition; only options that already clear it are considered here.

---

## 2. Decision: libkrun via `crun --krun` (single Linux backend)

### 2.1 What it is

[`containers/libkrun`](https://github.com/containers/libkrun) is a Rust user-space VMM whose code is partly derived from Firecracker, Cloud Hypervisor, and the [`rust-vmm`](https://github.com/rust-vmm) crates ([RUNTIMES.md §4.4](./RUNTIMES.md)).

[`crun`](https://github.com/containers/crun) is a fast OCI runtime; passing `--krun` makes `crun` boot the OCI bundle inside a libkrun microVM instead of a namespaces-only container. Podman drives the whole thing as a normal OCI runtime: `podman --runtime krun run <image>`.

Networking uses **TSI (Transparent Socket Impersonation)**: in-guest sockets are transparently forwarded to host sockets through libkrun, with **no TAP device, bridge, NAT, or `slirp4netns` plumbing on the host side** ([RUNTIMES.md §4.4](./RUNTIMES.md), libkrun upstream).

### 2.2 Why it wins on each criterion

**Criterion 1 — security.**

- **KVM-class boundary.** The guest runs its own kernel; the host kernel is not part of the in-guest attack surface. Shared-kernel escape classes (runc, namespaces, seccomp bypasses) do not apply at this boundary.
- **No published hypervisor-escape CVEs in libkrun 2024–2026.** The two libkrun CVEs in 2025 were transitive Rust dependency rolls (`rust-openssl`, `crossbeam-channel`), patched through the normal Fedora pipeline; neither was a VMM escape. References: [FEDORA-2025-f8be7978e3](https://linuxsecurity.com/advisories/fedora/fedora-41-libkrun-2025-f8be7978e3-security-advisory-updates-rh8lbifoalx6), [FEDORA-2025-c53905e83d](https://linuxsecurity.com/advisories/fedora/fedora-41-libkrun-2025-c53905e83d-ohmxvt9uvrww).
- **TSI removes host-side TAP/bridge/NAT plumbing** in exchange for a userspace proxy that terminates per-connection TCP on the **host's** TCP/IP stack via real `AF_INET` / `AF_INET6` / `AF_UNIX` sockets ([libkrunfw TSI patch](https://github.com/containers/libkrunfw/blob/main/patches/0009-Transparent-Socket-Impersonation-implementation.patch)). This is a **different** host-side network surface from a TAP+netfilter microVM, not a strictly smaller one. The Phase 5 in-VM nftables egress allowlist ([IMPLEMENTATION-PLAN.md §Phase 5](./IMPLEMENTATION-PLAN.md)) is sized for exactly this trade-off: the egress proxy lives in the VMM process, so per-VM allowlisting is the right control point.
- **Trust path vs. boundary class.** libkrun + crun + Podman is more code on the host-side trust path than a minimal bare-VMM stack, but the **boundary class is identical (KVM)**. Boundary class is the security-relevant variable; trust-path size is a secondary consideration weighed against engineering cost (see §2.4).
- **Device-set delta vs. bare Firecracker (the residual host-kernel surface).** Every KVM VMM keeps `/dev/kvm` ioctls and a set of virtio device backends as the host-facing surface — see [SPEC.md §4.1 "Residual host-kernel surface"](./SPEC.md). libkrun's set is **wider** than Firecracker's in three concrete ways: (1) **virtio-fs is the default rootfs path** — it is how `crun --krun` mounts the OCI bundle into the guest — whereas Firecracker has no virtio-fs and forces a devmapper-snapshotter detour in Kata-on-FC; (2) **TSI's host-side proxy** opens real host AF_INET sockets on behalf of the guest, terminating per-connection TCP state on the host kernel; (3) **virtio-gpu (virgl/venus)** is available via `krun_set_gpu_options` and is off by default in this implementation. This delta is the technical content behind the maintainer's framing in [libkrun #538](https://github.com/containers/libkrun/discussions/538) ("guest and VMM pertain to the same security context") and is accepted as the cost of the smaller adapter footprint per §2.4. None of these surfaces converts the boundary back to shared-kernel — a guest-kernel LPE remains a guest-kernel compromise, not a host compromise — but they are the right thing to evaluate when comparing libkrun against a minimal bare-VMM stack.

**Criterion 2 — production-proven and well-maintained.**

- Lives under [`containers/`](https://github.com/containers) — same org as Podman, crun, Buildah, Skopeo. The deepest investment in OCI-native rootless workflows in the ecosystem.
- v1.18.0 shipped 2026-04-24 (see [`RUNTIMES.md` §4.4](./RUNTIMES.md)); active commit cadence.
- Concrete production users:
  - **RamaLama** — Red Hat's primary AI-isolation story for local model execution. See [Red Hat Developer — "Supercharging AI isolation: microVMs with RamaLama and libkrun" (Jul 2025)](https://developers.redhat.com/articles/2025/07/02/supercharging-ai-isolation-microvms-ramalama-libkrun).
  - **Microsandbox** — open-source sandboxing platform built on libkrun.
  - **krunvm** — `containers/krunvm` CLI for libkrun microVMs.

**Criterion 3 — clean UX.**

- `podman --runtime krun run <image>` consumes the existing `images/` OCI artifacts directly. **No rootfs builder, no kernel-image lifecycle, no in-guest agent, no containerd shim, no devmapper snapshotter.**
- The runtime adapter sketched in [SPEC.md §5.5](./SPEC.md) (`lib/dctl/runtime/krun.sh`) collapses to ~80–150 lines of Bash that adds `--runtime krun` to existing Podman calls.
- TSI eliminates the entire host-side networking plumbing class (TAP/bridge/NAT/`slirp4netns`).
- The authoring surface (`devcontainer.json`, manifest layers, `runtime:` field) does not change. The composition system from `schemas/compose.schema.yaml` keeps working.

**Criterion 4 — single working Linux implementation.**

- KVM is available on essentially every modern Linux developer workstation; for the rare KVM-less CI runner case, gVisor covers the gap (§3).
- One adapter, one manifest field value, one OCI build pipeline. No cross-platform shim, no escape-hatch maintenance, no parallel backend to keep at feature parity.
- The scope is exactly *one* runtime adapter built, tested, and shipped.

**Criterion 5 — migration is cheap.**

- The adapter is small enough to rewrite as a Rust binary later without throwing away domain knowledge — the OCI image artifacts, the manifest schema, the layer composition, the Tier-0 egress/mount policies, and the runtime-agnostic `lib/dctl/` modules all stay.
- If we ever decide to swap libkrun for a different backend, it is a single `lib/dctl/runtime/<name>.sh` module change behind the same `rt_run`/`rt_exec`/`rt_ps`/`rt_rm`/`rt_build` interface ([SPEC.md §5.5](./SPEC.md)).

### 2.3 What `dctl` owns vs. what is upstream

| Owned by `dctl` | Owned upstream |
|---|---|
| `lib/dctl/runtime/krun.sh` adapter (~80–150 LOC bash). | Rootfs construction (handled inside `crun-krun`). |
| `runtime.name: krun` value in `schemas/compose.schema.yaml`. | Kernel image (libkrun bundles or fetches it). |
| KVM-detection probe with a clear error message when KVM is missing. | In-guest init / agent. |
| Tier-0 policies (egress allowlist, scoped/ephemeral mounts, `no-new-privileges`, `cap-drop=ALL`). Runtime-agnostic. | KVM interface, virtio devices. |
| Rootless-Podman defaults (pasta networking, `userns=auto:size=65536`) — already needed for [SPEC.md §5.2 Tier 1](./SPEC.md). | TSI networking (no TAP/bridge plumbing). |
| Choice of which `devcontainer.json` keys are honored vs. produce a clear error under `krun`. | OCI runtime spec compliance via `crun`. |

### 2.4 Comparison cost (illustrative, drawn from [RUNTIMES.md](./RUNTIMES.md))

| Option | `dctl`-owned plumbing surface |
|---|---|
| libkrun via `crun --krun` (chosen) | A flag and an adapter (~80–150 LOC bash). |
| Bare Firecracker | Rootfs builder + TAP/NAT + in-guest init + vsock channel + kernel updates → ~3–5 calendar weeks one-time and a permanent maintenance tail. |
| Kata + Firecracker | containerd shim + runtime-class registration + **devmapper snapshotter** (no virtio-fs on FC) → real laptop friction. |
| Kata + Cloud Hypervisor | containerd shim + runtime-class registration; cleaner than Kata-FC; still containerd. |

### 2.5 Why not bare Firecracker

Bare Firecracker has the smallest TCB of any option in [RUNTIMES.md](./RUNTIMES.md) — ~50–83K LoC of Rust, zero published hypervisor-escape CVEs 2024–2026, and an [arXiv microarchitectural-security analysis](https://arxiv.org/pdf/2311.15999) to back the claim. Recent CVEs are scoped: **CVE-2026-5747** is in virtio-pci and only affects the opt-in `--enable-pci` flag (default MMIO is unaffected), per [AWS bulletin 2026-015](https://aws.amazon.com/security/security-bulletins/2026-015-aws/); **CVE-2026-1386** is a host-side jailer symlink LPE, per [AWS bulletin 2026-003](https://aws.amazon.com/security/security-bulletins/rss/2026-003-aws/). Neither is a hypervisor escape.

It is **not** part of this implementation for the following reasons:

- **Boundary class is identical to libkrun (KVM).** The security-relevant axis — separate guest kernel, no shared-kernel boundary — is satisfied equally by both. A smaller VMM TCB tightens the host-side trust path but does **not** raise the isolation class.
- **Implementation cost.** `dctl` would own the rootfs builder, kernel image lifecycle, in-guest init, vsock exec channel, TAP/NAT plumbing, and a controller binary (~3–5 calendar weeks one-time and a permanent maintenance tail per [DECISION.md §2.5](./DECISION.md)). This violates criterion 3 (clean UX, minimal owned plumbing) and criterion 4 (single working implementation).
- **Status in the catalog.** Retained as a catalog item in [DECISION.md §2.5](./DECISION.md) for future opt-in. Not built here.

### 2.6 Why not Kata-FC or Kata-CH

Kata Containers (Firecracker or Cloud Hypervisor variant) is the technically closest alternative on the boundary axis (same KVM class). It is **not** part of this implementation because:

- **Containerd dependency.** Both Kata-FC and Kata-CH assume a containerd + runtime-class registration on the host. That is the largest piece of cluster-shaped infrastructure in the candidate set and directly violates criterion 3 (clean UX) — `dctl` would have to own a containerd lifecycle on developer workstations and CI runners.
- **No security delta over libkrun.** Both deliver a KVM-class boundary; choosing Kata trades adapter simplicity for cluster-shaped tooling without isolating against any additional attack class relevant to the stated threat model.
- **Kata-FC adds devmapper snapshotter friction** (no virtio-fs on Firecracker; see [RUNTIMES.md §4.2](./RUNTIMES.md)).
- **Status in the catalog.** Kata-CH remains in [DECISION.md §2.4](./DECISION.md) as a deferred contingency adapter if libkrun's governance or maintenance posture deteriorates. Not built here.

### 2.7 Why not gVisor as primary

gVisor is a *different* boundary class — userspace kernel rather than hardware-virtualization — used in production by Modal and Cloud Run ([RUNTIMES.md §3.1](./RUNTIMES.md)). It is excellent for its niche, but criterion 1 requires a hardware-virtualization boundary as the primary. gVisor's `runsc` bugs land host-side. It is therefore used **only** where KVM is unavailable, and only on CI runners (§3).

---

## 3. Decision: gVisor (no-KVM CI fallback only)

gVisor is documented as a **CI-only fallback** for environments without KVM (containerized CI runners, cloud VMs without nested virtualization). It is a drop-in OCI runtime with full OCI fit and active Google maintenance ([RUNTIMES.md §3.1](./RUNTIMES.md)).

**Important boundary qualifier.** gVisor is **not** a second supported backend for developer workstations. The CI threat model explicitly accepts the weaker boundary class because the workload there is the project's own test code, not adversarial LLM-generated code; the dev-workstation threat model — running LLM agents — requires the hardware-virtualization boundary that libkrun provides.

This resolves [SPEC.md §8 — "CI parity"](./SPEC.md): **gVisor on KVM-less CI environments, libkrun everywhere else.**

---

## 4. Out of scope

| Item | Rationale | Status |
|---|---|---|
| **macOS / Apple `container`** | This implementation is Linux-only. macOS support adds a second backend and a parallel feature-parity matrix; not part of the single-implementation goal. | Catalog-only in [DECISION.md §3](./DECISION.md). |
| **Bare Firecracker** | Same boundary class as libkrun; the smaller VMM TCB does not raise isolation class and costs ~3–5 calendar weeks of owned plumbing. | Catalog-only in [DECISION.md §2.5](./DECISION.md). |
| **Kata-FC** | Containerd dependency; devmapper snapshotter friction; no security delta. | Dropped in [DECISION.md §7](./DECISION.md). |
| **Kata-CH** | Containerd dependency; no security delta. Reserved as a deferred contingency adapter in case libkrun governance deteriorates. | Catalog-only in [DECISION.md §7](./DECISION.md). |
| **libkrun-on-HVF parity tracking** | macOS-specific; not relevant when macOS is out of scope. | Tracked upstream; ignored here. |
| **Multi-backend manifest selection** | This implementation ships exactly one accepted backend value (`runtime.name: krun`); the gvisor CI fallback is described in prose only and will be added to the schema enum when the adapter lands. | Schema future-compatible; not exposed here. |

---

## 5. Resolved open questions

The following questions from [SPEC.md §8](./SPEC.md) are resolved:

| Question | Resolution |
|---|---|
| Final §4.1 backend choice | **libkrun via `crun --krun`** on Linux. |
| CI parity default | **gVisor** on no-KVM CI runners; **libkrun** where KVM is available. |
| Image distribution: Kata-specific or libkrun-specific build target? | **No new build target.** libkrun consumes the existing `images/` OCI artifacts unchanged via `crun --krun`. |
| Multi-backend selection at the manifest level | Schema-ready; **not exposed** in this implementation. Only `runtime.name: krun` is accepted by `schemas/compose.schema.yaml`; the gvisor CI fallback is documented in prose and will be added to the schema enum together with its adapter. |

These remain unaffected by this decision and apply runtime-agnostically:

- **Token forwarding** — independent of runtime; tracked in [SPEC.md §8](./SPEC.md).
- **Egress allowlist UX** — independent of runtime.
- **Cross-runtime feature parity** — the runtime adapter must define which `devcontainer.json` keys are portable; the rest must error explicitly rather than silently degrade.

### 5.1 Phase-40 egress enforcement

libkrun's TSI removes host-side TAP and bridge plumbing, but it does not apply
an outbound policy on its own. Round 40 therefore installs a per-VM egress
policy inside the guest with nftables (Option A). The control surface lives in
`lib/dctl/commands/net/` and the in-guest bootstrap script
`images/agents/dctl-egress`.

Option B, a userspace `dctl-proxy`, is rejected for this round. It would add a
new binary, new HTTP/TLS interception semantics, and a larger support surface
without changing the underlying isolation class. Revisit it only if DNS
rotation or wildcard-host ergonomics prove untenable in practice.

---

## 6. Risks accepted

Each risk is logged so it can be re-evaluated if conditions change.

1. **Trust path is longer than a minimal bare-VMM stack, and libkrun's host-facing device set is wider than Firecracker's.** Two separable facets:
   - **Host-side TCB outside the VMM.** libkrun + crun + Podman is more code on the host-side trust path than `jailer` + `firecracker`. **Same boundary class (KVM); larger TCB outside the VMM.**
   - **Host-facing device-backend surface.** libkrun retains three host-side surfaces that bare Firecracker either does not have or implements differently: **virtio-fs as the default rootfs path** (Firecracker has none; Kata-on-FC pays a devmapper snapshotter cost for the same reason), **TSI's userspace proxy** terminating per-connection TCP on the host's `AF_INET` stack (Firecracker uses TAP+netfilter instead), and **virtio-gpu (virgl/venus)** available via `krun_set_gpu_options` (Firecracker has no GPU support at all). The first two are unavoidable under this design; the third is **off by default in this implementation** and is gated behind an explicit profile opt-in to keep the surface bounded. See [SPEC.md §4.1 "Residual host-kernel surface"](./SPEC.md) for the full framing.

   Both facets are accepted in exchange for ~3–5 calendar weeks of plumbing that `dctl` does not have to own. The bare-FC adapter remains documented in [DECISION.md §2.5](./DECISION.md) for future opt-in where minimizing this surface is worth the cost.
2. **KVM is a hard requirement on developer workstations.** Hosts without KVM are not supported as workstation targets in this implementation. CI runners without KVM fall back to gVisor, with the understood weaker boundary class.
3. **Single-vendor concentration in the `containers/` org.** Podman, crun, libkrun, Buildah, Skopeo all live under one org. Healthy in 2026; if funding or governance shifts, several `dctl` dependencies move at once. Mitigation: Kata-CH adapter remains specified in the catalog as a backup with different governance (CNCF incubating).
4. **Shared `rust-vmm` lineage.** libkrun is derived from Firecracker, Cloud Hypervisor, and the `rust-vmm` crates ([RUNTIMES.md §4.4](./RUNTIMES.md)). A class bug in shared `rust-vmm` crates would land on libkrun, Firecracker, **and** Cloud Hypervisor simultaneously — runtime swap is not a mitigation. The mitigation is `dctl`'s own CVE-watch and a quick path to apply upstream patches. Recent precedent: the Firecracker virtio-pci OOB write in CVE-2026-5747 ([AWS bulletin 2026-015](https://aws.amazon.com/security/security-bulletins/2026-015-aws/)) is a reminder that "small VMM" is not "no VMM CVEs."
5. **Token-exfiltration and credential-leakage risks are runtime-independent.** Runtime selection does not solve credential leakage from bind-mounted host config (`~/.config/gh`, `~/.config/glab-cli`, `~/.claude*`). Those risks are addressed by the Tier-0 policies in [SPEC.md §5.2](./SPEC.md) — scoped/ephemeral token forwarding, no host-`/tmp` bind, `no-new-privileges`, `cap-drop=ALL` — and apply equally to any runtime.

---

## 7. Migration plan (delta from [SPEC.md §5–6](./SPEC.md))

This decision narrows [SPEC.md §5–6](./SPEC.md) but does not change its tier structure.

- **Tier 0 (configuration hygiene)** — unchanged. Tier-0 changes apply regardless of runtime.
- **Tier 1 (runtime abstraction)** — unchanged. Podman-rootless lands as a backend and as a controller front-end for libkrun. The runtime adapter interface (`rt_run`, `rt_exec`, `rt_ps`, `rt_rm`, `rt_build`) is the contract everything else hangs on.
- **Tier 2 (hardware-virt boundary)** — narrowed for this implementation:
  - **T2.1c (libkrun adapter)** is the **default and the only built path**.
  - **T2.3 (gVisor adapter)** ships as the no-KVM CI fallback.
  - **T2.1a (Kata-FC), T2.1b (Kata-CH), T2.1d (bare Firecracker), T2.2 (Apple `container`)** are **out of scope here**; they remain specified in the catalog for future adoption behind the same adapter interface.
- **Tier 3** — unchanged. Once libkrun is the default, the inner-container freedom can be expanded per [SPEC.md §5.4](./SPEC.md).

**Concrete next step:** implement `lib/dctl/runtime/krun.sh` against the [SPEC.md §5.5](./SPEC.md) adapter sketch and run the standard smoke-test against it on a KVM-capable Linux host. The numbers (cold-start, mount latency, devcontainer-feature parity, smoke-test pass rate) close the prototyping milestone in [SPEC.md §4.4 / §6 T2.0](./SPEC.md).

Round 20 intentionally leaves Podman rootless network backend selection unpinned in `rt_run`. Under the chosen libkrun design, TSI already removes the host-side TAP/bridge/NAT plumbing class discussed above ([§2.1](#21-what-it-is), [§2.2](#22-why-it-wins-on-each-criterion)), so there is no round-20 evidence forcing a `slirp4netns` vs `pasta` override on the krun path. A later smoke pass can revisit pinning if a concrete compatibility or performance preference emerges, but for now the implementation keeps the runtime unpinned and treats backend choice as deferred rather than guessed.

---

## 8. References

### Primary sources (project-internal)

- [SPEC.md](./SPEC.md) — premises (§1), threat model (§3), candidate set (§4), tiered migration (§5–§6), open questions (§8).
- [RUNTIMES.md](./RUNTIMES.md) — per-option catalog. Relevant entries: §3.1 (gVisor), §4.1 (bare Firecracker), §4.2 (Kata + FC), §4.3 (Kata + CH), §4.4 (libkrun + `crun --krun`).
- [DECISION.md](./DECISION.md) — catalog-level decision, retained for reference. This document narrows it to a single backend.

### libkrun / `crun --krun` / Podman

- [containers/libkrun](https://github.com/containers/libkrun) — upstream repository.
- [crun `krun.1` manpage](https://manpages.opensuse.org/Tumbleweed/crun/krun.1.en.html) — `crun --krun` invocation contract.
- [containers/krunvm](https://github.com/containers/krunvm) — reference CLI built on libkrun.
- [Red Hat Developer — "Supercharging AI isolation: microVMs with RamaLama and libkrun" (Jul 2025)](https://developers.redhat.com/articles/2025/07/02/supercharging-ai-isolation-microvms-ramalama-libkrun) — production-use evidence.
- [libkrun discussion #538 — security model](https://github.com/containers/libkrun/discussions/538) — maintainer's threat-model framing ("guest and VMM pertain to the same security context").

### libkrun CVE evidence

- [Fedora FEDORA-2025-f8be7978e3 — libkrun (rust-openssl dependency roll)](https://linuxsecurity.com/advisories/fedora/fedora-41-libkrun-2025-f8be7978e3-security-advisory-updates-rh8lbifoalx6).
- [Fedora FEDORA-2025-c53905e83d — libkrun (crossbeam-channel dependency roll)](https://linuxsecurity.com/advisories/fedora/fedora-41-libkrun-2025-c53905e83d-ohmxvt9uvrww).

### Kata + Cloud Hypervisor (deferred catalog references)

- [Kata Containers homepage](https://katacontainers.io/).
- [Kata Containers — "Kata + Cloud Hypervisor" blog](https://katacontainers.io/blog/kata-containers-with-cloud-hypervisor/).
- [Northflank — "Kata vs Firecracker vs gVisor"](https://northflank.com/blog/kata-containers-vs-firecracker-vs-gvisor).
- [Northflank — "Cloud Hypervisor 2026 guide"](https://northflank.com/blog/guide-to-cloud-hypervisor).
- [AWS — "Enhancing Kubernetes workload isolation with Kata"](https://aws.amazon.com/blogs/containers/enhancing-kubernetes-workload-isolation-and-security-using-kata-containers/).
- [Cloud Hypervisor — Landlock docs](https://github.com/cloud-hypervisor/cloud-hypervisor/blob/main/docs/landlock.md).
- [Cloud Hypervisor release notes](https://github.com/cloud-hypervisor/cloud-hypervisor/blob/main/release-notes.md).

### Firecracker (catalog references; CVE precedent)

- [Firecracker design.md](https://github.com/firecracker-microvm/firecracker/blob/main/docs/design.md).
- [AWS — "Firecracker open source secure fast microVM serverless"](https://aws.amazon.com/blogs/opensource/firecracker-open-source-secure-fast-microvm-serverless/).
- [Microarchitectural Security of AWS Firecracker VMM (arXiv 2311.15999)](https://arxiv.org/pdf/2311.15999).
- [AWS bulletin 2026-015 — CVE-2026-5747 (virtio-pci OOB write; opt-in `--enable-pci`)](https://aws.amazon.com/security/security-bulletins/2026-015-aws/).
- [AWS bulletin 2026-003 — CVE-2026-1386 (jailer symlink LPE; host-side)](https://aws.amazon.com/security/security-bulletins/rss/2026-003-aws/).
- [edera.dev — "Minimal is no longer enough: why AI-scale vulnerability discovery changes container security"](https://edera.dev/stories/minimal-is-no-longer-enough-why-ai-scale-vulnerability-discovery-changes-container-security).

### gVisor (no-KVM CI fallback)

- [gvisor.dev — docs](https://gvisor.dev/docs/).
- [gvisor.dev — performance guide](https://gvisor.dev/docs/architecture_guide/performance/).

### Shared-kernel CVE precedent (why bare containers are not the boundary)

- [Sysdig — "runc container escape vulnerabilities" (Nov 2025)](https://www.sysdig.com/blog/runc-container-escape-vulnerabilities) — CVE-2025-31133, CVE-2025-52565, CVE-2025-52881.
- [CNCF — "runc container breakout vulnerabilities: a technical overview" (Nov 2025)](https://www.cncf.io/blog/2025/11/28/runc-container-breakout-vulnerabilities-a-technical-overview/).
- [emirb — "microvm-2026"](https://emirb.github.io/blog/microvm-2026/) — hypervisor-escape bug-class economics.
