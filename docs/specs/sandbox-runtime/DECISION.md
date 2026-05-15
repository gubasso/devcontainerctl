# Sandbox Runtime — Decision

> Status: Decided
> Decision date: 2026-05-07
> Scope: Selection of the primary default backend for `devcontainerctl` (`dctl`).
> Companions: [SPEC.md](./SPEC.md) (premises, threat model, tiered migration), [RUNTIMES.md](./RUNTIMES.md) (per-option catalog).
> Supersedes: SPEC.md §4 (which deferred the choice) and SPEC.md §8 open question "Final §4.1 backend choice".

## 0. Summary

The primary default backend is **libkrun via `crun --krun`, fronted by Podman-rootless** on Linux.
The macOS path is **Apple `container`** (Virtualization.framework, macOS 26+).
The no-KVM fallback is **gVisor (`runsc`)**.

These three slots together satisfy the §1 premises (hardware-virt boundary, OCI-driven authoring, cross-platform, acceptable cold-start) with the smallest amount of code `dctl` has to own and maintain.

| Slot | Pick | Rationale (one line) |
|---|---|---|
| Linux primary | **libkrun + `crun --krun`** | KVM-class boundary, OCI-native, smallest adapter footprint of any §4.1 candidate. |
| macOS primary | **Apple `container`** | HVF-class boundary; native Apple toolchain; libkrun-on-HVF parity is not there yet. |
| No-KVM fallback | **gVisor** | Userspace-kernel sandbox; only viable answer for CI runners and cloud VMs without nested virt. |
| Documented escape hatch | **Bare Firecracker** | Smallest TCB if a project needs to opt into the high-assurance path; built on the same adapter interface but never the default. |

This decision intentionally does **not** select Kata Containers (FC or CH) as the default. See §3.4.

---

## 1. Decision criteria

These criteria override the more even-handed "tie-breaker" framing in [SPEC.md §4.4](./SPEC.md). They were stated by the project maintainer on 2026-05-07; in priority order:

1. **Production-proven and well-maintained.** Active upstream, real users, stable cadence, healthy CVE response.
2. **Enables clean UX.** The project's design premises — simple commands, declarative + composable + shareable manifests — must be preserved. The amount of plumbing `dctl` itself has to own is the dominant UX cost.
3. **Not bound to the VS Code `devcontainer` CLI.** Pick the leanest, cleanest, most secure option even if it means dropping `devcontainer up` compatibility.
4. **Migration is cheap.** A future Rust rewrite or full refactor is acceptable; do not over-weight switching cost when picking now.

The §1.1 hardware-virt premise from [SPEC.md](./SPEC.md) (KVM-class or HVF-class boundary, no shared kernel) is a precondition; only options that already clear it are considered here.

---

## 2. Decision: libkrun via `crun --krun` (Linux primary)

### 2.1 What it is

[`containers/libkrun`](https://github.com/containers/libkrun) is a Rust user-space VMM whose code is partly derived from Firecracker, Cloud Hypervisor, and the [`rust-vmm`](https://github.com/rust-vmm) crates ([RUNTIMES.md §4.4](./RUNTIMES.md)). [`crun`](https://github.com/containers/crun) is a fast OCI runtime; passing `--krun` makes `crun` boot the OCI bundle inside a libkrun microVM instead of a namespaces-only container. Podman drives the whole thing as a normal OCI runtime: `podman --runtime krun run <image>`.

Networking uses **TSI (Transparent Socket Impersonation)**: in-guest sockets are transparently forwarded to host sockets through libkrun, with no TAP device, bridge, NAT, or `slirp4netns` plumbing on the host side ([RUNTIMES.md §4.4](./RUNTIMES.md), libkrun upstream).

### 2.2 Why it wins on each criterion

**Criterion 1 — production-proven and well-maintained.**
- Lives under [`containers/`](https://github.com/containers) — same org as Podman, crun, Buildah, Skopeo. The deepest investment in OCI-native rootless workflows in the ecosystem.
- v1.18.0 shipped 2026-04-24 (see [`RUNTIMES.md` §4.4](./RUNTIMES.md)); active commit cadence; cross-platform (Linux KVM and macOS HVF backends).
- Concrete production users:
  - **RamaLama** — Red Hat's primary AI-isolation story for local model execution. See [Red Hat Developer — "Supercharging AI isolation: microVMs with RamaLama and libkrun" (Jul 2025)](https://developers.redhat.com/articles/2025/07/02/supercharging-ai-isolation-microvms-ramalama-libkrun).
  - **Microsandbox** — open-source sandboxing platform built on libkrun.
  - **krunvm** — `containers/krunvm` CLI for libkrun microVMs.
- No published hypervisor-escape CVEs in libkrun itself (2024–2026). The two libkrun CVEs that surfaced in 2025 were transitive Rust dependency rolls (`rust-openssl`, `crossbeam-channel`) and were patched through the normal Fedora pipeline, not VMM escapes. References: [FEDORA-2025-f8be7978e3](https://linuxsecurity.com/advisories/fedora/fedora-41-libkrun-2025-f8be7978e3-security-advisory-updates-rh8lbifoalx6), [FEDORA-2025-c53905e83d](https://linuxsecurity.com/advisories/fedora/fedora-41-libkrun-2025-c53905e83d-ohmxvt9uvrww).

**Criterion 2 — enables clean UX.** This is where libkrun pulls decisively ahead.
- `podman --runtime krun run <image>` consumes the existing `images/` OCI artifacts directly. **No rootfs builder, no kernel-image lifecycle, no in-guest agent, no containerd shim, no devmapper snapshotter.**
- The runtime adapter sketched in [SPEC.md §5.5](./SPEC.md) (`lib/dctl/runtime/krun.sh`) collapses to ~80–150 lines of Bash that adds `--runtime krun` to existing Podman calls.
- TSI eliminates the entire host-side networking plumbing class (TAP/bridge/NAT/`slirp4netns`).
- The user-facing surface (`devcontainer.json`, manifest layers, `runtime:` field) does not change. The composition system from `schemas/compose.schema.yaml` keeps working.

**Criterion 3 — not bound to `devcontainer` CLI.** This criterion quietly disqualifies Kata for the default.
- Kata-on-FC and Kata-on-CH assume **containerd** + a runtime-class registration; their UX wins lean on `nerdctl` and Kubernetes, not on `devcontainer up`. To use them at the laptop level you either keep the `devcontainer` CLI (and pay for the legacy plumbing) or rebuild the lifecycle yourself on top of containerd (and own a containerd dependency).
- libkrun assumes **Podman rootless** — a single, well-documented controller. Dropping `devcontainer up` in favour of `podman --runtime krun ...` is a clean cut: image authoring stays OCI, runtime invocation stops going through Microsoft's CLI, and the schema is unchanged.

**Criterion 4 — migration is cheap.** This is also where libkrun pays off.
- The adapter is small enough to rewrite as a Rust binary later without throwing away domain knowledge — the OCI image artifacts, the manifest schema, the layer composition, the Tier-0 egress/mount policies, and the runtime-agnostic `lib/dctl/` modules all stay.
- If we ever decide to swap libkrun for Kata-CH or bare-Firecracker, it is a single `lib/dctl/runtime/<name>.sh` module change behind the same `rt_run`/`rt_exec`/`rt_ps`/`rt_rm`/`rt_build` interface ([SPEC.md §5.5](./SPEC.md)).

### 2.3 What `dctl` owns vs. what is upstream

| Owned by `dctl` | Owned upstream |
|---|---|
| `lib/dctl/runtime/krun.sh` adapter (~80–150 LOC bash). | Rootfs construction (handled inside `crun-krun`). |
| `runtime: krun` value in `schemas/compose.schema.yaml`. | Kernel image (libkrun bundles or fetches it). |
| KVM-detection probe with a clear error message when KVM is missing. | In-guest init / agent. |
| Tier-0 policies (egress allowlist, scoped/ephemeral mounts, `no-new-privileges`, `cap-drop=ALL`). These are runtime-agnostic anyway. | KVM/HVF interface, virtio devices. |
| Rootless-Podman defaults (pasta networking, `userns=auto:size=65536`) — already needed for [SPEC.md §5.2 Tier 1](./SPEC.md). | TSI networking (no TAP/bridge plumbing). |
| Choice of which `devcontainer.json` keys are honored vs. produce a clear error under `krun`. | OCI runtime spec compliance via `crun`. |

**Comparison cost (illustrative, drawn from [RUNTIMES.md](./RUNTIMES.md)):**
- Bare Firecracker: rootfs builder + TAP/NAT + in-guest init + vsock channel + kernel updates → ~3–5 calendar weeks one-time and a permanent maintenance tail.
- Kata + Firecracker: containerd shim + runtime-class registration + **devmapper snapshotter** (no virtio-fs on FC) → real laptop friction.
- Kata + Cloud Hypervisor: containerd shim + runtime-class registration; cleaner than Kata-FC; still containerd.
- libkrun via `crun --krun`: a flag and an adapter.

### 2.4 Why not Kata-CH (the runner-up)

Kata + Cloud Hypervisor is the *technically closest* alternative — same KVM boundary class, virtio-fs avoids the devmapper trap that hurts Kata-FC, and it is the path the Kata community actively exercises in production ([RUNTIMES.md §4.3](./RUNTIMES.md), [Northflank — Kata vs Firecracker vs gVisor](https://northflank.com/blog/kata-containers-vs-firecracker-vs-gvisor), [AWS — Enhancing Kubernetes workload isolation with Kata](https://aws.amazon.com/blogs/containers/enhancing-kubernetes-workload-isolation-and-security-using-kata-containers/)).

We pass on it because:

1. **It pulls in containerd as a hard dependency** for laptop use. That is the largest piece of cluster-shaped infrastructure in the candidate set, and it directly violates criterion 3 ("lean, clean").
2. **No UX delta over libkrun** for the `dctl` use case (single-developer agent VM, OCI image in, exec out). The Kata feature surface (snapshotters, runtime classes, multi-tenant scheduling) is built for Kubernetes, not for `dctl`.
3. **Switching cost is bounded.** If libkrun stalls or its trust model becomes uncomfortable, swapping to Kata-CH is a new `runtime/kata-ch.sh` module behind the same adapter interface ([SPEC.md §5.5](./SPEC.md)). Criterion 4 explicitly accepts that.

We will switch to Kata-CH if:
- libkrun's macOS HVF parity fails to close the bind-mount gap ([containers/podman#27679](https://github.com/containers/podman/discussions/27679)) and we decide to standardize on a single Linux backend across both platforms.
- We start needing containerd-native features (snapshotters, image GC, multi-tenant scheduling) that libkrun's intentional smallness omits.

### 2.5 Why not bare Firecracker (the high-assurance escape hatch)

Bare Firecracker has the **smallest TCB** of any option in [RUNTIMES.md](./RUNTIMES.md) — ~50–83K LoC of Rust, zero published hypervisor-escape CVEs in 2024–2026, and an `arXiv` microarchitectural-security analysis to back the claim ([2311.15999](https://arxiv.org/pdf/2311.15999)). Recent CVEs are scoped: **CVE-2026-5747** is in virtio-pci and only affects the opt-in `--enable-pci` flag (default MMIO is unaffected), per [AWS bulletin 2026-015](https://aws.amazon.com/security/security-bulletins/2026-015-aws/); **CVE-2026-1386** is a host-side jailer symlink LPE, per [AWS bulletin 2026-003](https://aws.amazon.com/security/security-bulletins/rss/2026-003-aws/). Neither is a hypervisor escape.

It is **not** the default because the implementation cost violates criterion 2:
- `dctl` would own the rootfs builder, kernel image lifecycle, in-guest init, vsock exec channel, TAP/NAT plumbing, and a controller binary (~3–5 calendar weeks one-time + ongoing).
- That is exactly the work libkrun lets us avoid while landing on the same boundary class.

It stays in the catalog and gets a `runtime/bare-fc.sh` module ([SPEC.md §5.5](./SPEC.md)) as a documented escape hatch for users who explicitly want the smallest TCB on the host.

### 2.6 Why not gVisor as primary

gVisor is a *different* boundary (userspace kernel rather than hypervisor), used in production by Modal and Cloud Run ([RUNTIMES.md §3.1](./RUNTIMES.md)). It is excellent — but criterion 1 of [SPEC.md §1.1](./SPEC.md) requires a hardware-virtualization boundary as the primary, and gVisor's `runsc` bugs land host-side. We use gVisor only where KVM is unavailable.

---

## 3. Decision: Apple `container` (macOS primary)

### 3.1 What it is

[`apple/container`](https://github.com/apple/container) is Apple's open-source Swift CLI (macOS 26+) that runs **one lightweight Linux VM per OCI container** via [Virtualization.framework](https://developer.apple.com/documentation/virtualization). Sub-second cold-start; native Apple silicon; OCI image input ([RUNTIMES.md §4.6](./RUNTIMES.md)).

### 3.2 Why it wins on macOS

- **Boundary class matches the §1.1 premise.** HVF/Virtualization.framework is the macOS equivalent of KVM-class isolation. "FC-for-Mac" is an accurate analogy.
- **OCI-native authoring surface** — same `images/` artifacts work.
- **Apple-backed maintenance.**
- **Maturity in 2026.** v0.8.0 (Jan 2026) is described upstream as "validation of concept, usable in specific scenarios." The `dctl` use case (single agent VM, OCI image in, exec out) is exactly that narrow shape. Reference: [Addo Zhang — "Apple container 0.8.0: seven-month evolution from birth to maturity" (Feb 2026)](https://addozhang.medium.com/apple-container-0-8-0-seven-month-evolution-from-birth-to-maturity-1021e570bbb7).
- **Why not libkrun's HVF backend?** It exists, but as of 2026 it has documented bind-mount permission gaps relative to Apple's `applehv` driver — see [containers/podman discussion #27679](https://github.com/containers/podman/discussions/27679) and [Sergio López on macOS GPU + virtio-fs](https://sinrega.org/2024-03-06-enabling-containers-gpu-macos/). Until those close, Apple `container` is the cleaner Mac story. This explicitly resolves [SPEC.md §8 — "Cross-platform mental model"](./SPEC.md).

### 3.3 What `dctl` owns vs. what is upstream

`lib/dctl/runtime/apple.sh` adapter (`container run`-style invocations); Tier-0 policies. Everything else — image conversion, VM lifecycle, networking — is upstream.

---

## 4. Decision: gVisor (no-KVM fallback)

Used only when KVM is unavailable (CI runners, cloud VMs without nested virt). Drop-in OCI runtime under containerd; full OCI fit; active Google maintenance ([RUNTIMES.md §3.1](./RUNTIMES.md)). Documented as **fallback**, not as a replacement for hardware isolation.

This resolves [SPEC.md §8 — "CI parity"](./SPEC.md): the documented CI default is **gVisor on KVM-less environments, libkrun on KVM-equipped environments**.

---

## 5. Resolved open questions

These were left open in [SPEC.md §8](./SPEC.md). This document closes them:

| Question | Resolution |
|---|---|
| Final §4.1 backend choice | **libkrun via `crun --krun`** on Linux. |
| Cross-platform mental model on macOS | **Two backends.** Apple `container` on macOS; libkrun on Linux. libkrun's HVF backend is tracked but is not yet at parity. |
| CI parity default | **gVisor** on no-KVM CI runners; libkrun where KVM is available. |
| Image distribution: Kata-specific or libkrun-specific build target? | **No new build target.** libkrun consumes the existing `images/` OCI artifacts unchanged via `crun --krun`. |

These remain open and are unaffected by this decision:

- **Claude session token forwarding** — independent of runtime; tracked in [SPEC.md §8](./SPEC.md).
- **Egress allowlist UX** — independent of runtime.
- **Cross-runtime feature parity** — the runtime adapter must define which `devcontainer.json` keys are portable across `krun`, `apple`, `gvisor`, `bare-fc`; the rest must error explicitly rather than silently degrade.

---

## 6. Risks accepted

The maintainer accepts the following risks as part of this decision. Each is logged so it can be re-evaluated if conditions change.

1. **Trust path is longer than bare-Firecracker.** libkrun + crun + Podman + rootless plumbing is more code on the host-side trust path than Firecracker's `jailer` → `firecracker` chain. Same boundary class (KVM); larger TCB *outside* the VMM. [SPEC.md §1.4](./SPEC.md) already accepts this trade for the plumbing-cost win. The bare-FC adapter remains as an escape hatch (§2.5).
2. **macOS HVF parity is not at Linux-KVM parity today.** [containers/podman#27679](https://github.com/containers/podman/discussions/27679) shows real bind-mount permission issues vs Apple's `applehv` driver. This is why we run two backends on macOS for now (Apple `container` is primary; libkrun-on-HVF is tracked).
3. **Single-vendor concentration in the `containers/` org.** Podman, crun, libkrun, Buildah, Skopeo all live under one org. Healthy in 2026; if funding shifts, several `dctl` dependencies move at once. Mitigation: Kata-CH adapter remains specified ([SPEC.md §5.5](./SPEC.md)) as a backup with different governance (CNCF incubating).
4. **Shared `rust-vmm` lineage.** libkrun is "derived from Firecracker, Cloud Hypervisor, and rust-vmm" ([RUNTIMES.md §4.4](./RUNTIMES.md)). A class bug in shared `rust-vmm` crates would land on libkrun, FC, **and** CH simultaneously — runtime swap is not a mitigation. The mitigation is `dctl`'s own CVE-watch and a quick path to apply upstream patches. Recent precedent: the FC virtio-pci OOB write in CVE-2026-5747 ([AWS 2026-015](https://aws.amazon.com/security/security-bulletins/2026-015-aws/)) is a reminder that "small VMM" is not "no VMM CVEs."
5. **Apple `container` is young (v0.8.0 in 2026).** It is fit-for-purpose for the narrow `dctl` shape today but may have rough edges (mount semantics, networking, GPU/Metal access) that we will discover during prototyping. Mitigation: ship behind `runtime: apple-container` and require explicit opt-in until smoke-test parity with the Linux primary is reached.
6. **libkrun's macOS HVF backend may never reach `applehv` parity.** If that happens, the long-term macOS story is permanently a separate runtime (Apple `container`) rather than a single mental model. Acceptable cost.

---

## 7. Migration plan (delta from SPEC.md §5–6)

This decision narrows [SPEC.md §5–6](./SPEC.md) but does not change its tier structure. The deltas are:

- **Tier 0 (configuration hygiene)** — unchanged. Tier-0 changes apply to all runtimes.
- **Tier 1 (runtime abstraction)** — unchanged. Podman-rootless lands as a backend and as a controller front-end for libkrun. The runtime adapter interface (`rt_run`, `rt_exec`, `rt_ps`, `rt_rm`, `rt_build`) is the contract everything else hangs on.
- **Tier 2 (FC-class hardware boundary)** — narrowed:
  - **T2.1c (libkrun adapter)** is the **default-default** path. Build it first.
  - **T2.2 (Apple `container` adapter)** ships in parallel and becomes the macOS default.
  - **T2.3 (gVisor adapter)** ships as the no-KVM fallback.
  - **T2.1a (Kata-FC)** is **dropped** from the implementation plan. Devmapper friction without a UX delta.
  - **T2.1b (Kata-CH)** is **deferred** as a contingency adapter only. Implement it if §6 risk #3 (single-vendor concentration) materializes or if libkrun's macOS HVF parity story fails terminally.
  - **T2.1d (bare Firecracker)** stays as a documented escape hatch, not a default.
- **Tier 3** — unchanged. Once libkrun is the default, the inner-container freedom can be expanded ([SPEC.md §5.4](./SPEC.md)).

**Concrete next step:** implement `lib/dctl/runtime/krun.sh` against the §5.5 adapter sketch and run the standard smoke-test against it on a KVM-capable Linux host. The numbers (cold-start, mount latency, devcontainer-feature parity, smoke-test pass rate) close the prototyping milestone in [SPEC.md §4.4 / §6 T2.0](./SPEC.md).

---

## 8. References

### Primary sources (project-internal)

- [SPEC.md](./SPEC.md) — premises (§1), threat model (§3), candidate set (§4), tiered migration (§5–§6), open questions (§8).
- [RUNTIMES.md](./RUNTIMES.md) — per-option catalog. Key entries for this decision: §3.1 (gVisor), §4.1 (bare Firecracker), §4.2 (Kata + FC), §4.3 (Kata + CH), §4.4 (libkrun + `crun --krun`), §4.6 (Apple `container`).

### libkrun / `crun --krun` / Podman

- [containers/libkrun](https://github.com/containers/libkrun) — upstream repository.
- [crun `krun.1` manpage](https://manpages.opensuse.org/Tumbleweed/crun/krun.1.en.html) — `crun --krun` invocation contract.
- [containers/krunvm](https://github.com/containers/krunvm) — reference CLI built on libkrun.
- [Red Hat Developer — "Supercharging AI isolation: microVMs with RamaLama and libkrun" (Jul 2025)](https://developers.redhat.com/articles/2025/07/02/supercharging-ai-isolation-microvms-ramalama-libkrun) — production-use evidence.
- [libkrun discussion #538 — security model](https://github.com/containers/libkrun/discussions/538) — maintainer's threat-model framing ("guest and VMM pertain to the same security context").
- [Sergio López — "Enabling containers GPU on macOS" (Mar 2024)](https://sinrega.org/2024-03-06-enabling-containers-gpu-macos/) — libkrun macOS background.
- [containers/podman discussion #27679 — libkrun vs `applehv` bind mounts](https://github.com/containers/podman/discussions/27679) — the parity gap on macOS.

### libkrun CVE evidence

- [Fedora FEDORA-2025-f8be7978e3 — libkrun (rust-openssl dependency roll)](https://linuxsecurity.com/advisories/fedora/fedora-41-libkrun-2025-f8be7978e3-security-advisory-updates-rh8lbifoalx6).
- [Fedora FEDORA-2025-c53905e83d — libkrun (crossbeam-channel dependency roll)](https://linuxsecurity.com/advisories/fedora/fedora-41-libkrun-2025-c53905e83d-ohmxvt9uvrww).

### Kata + Cloud Hypervisor (runner-up references)

- [Kata Containers homepage](https://katacontainers.io/).
- [Kata Containers — "Kata + Cloud Hypervisor" blog](https://katacontainers.io/blog/kata-containers-with-cloud-hypervisor/).
- [Northflank — "Kata vs Firecracker vs gVisor"](https://northflank.com/blog/kata-containers-vs-firecracker-vs-gvisor).
- [Northflank — "Cloud Hypervisor 2026 guide"](https://northflank.com/blog/guide-to-cloud-hypervisor).
- [AWS — "Enhancing Kubernetes workload isolation with Kata"](https://aws.amazon.com/blogs/containers/enhancing-kubernetes-workload-isolation-and-security-using-kata-containers/).
- [Cloud Hypervisor — Landlock docs](https://github.com/cloud-hypervisor/cloud-hypervisor/blob/main/docs/landlock.md).
- [Cloud Hypervisor release notes](https://github.com/cloud-hypervisor/cloud-hypervisor/blob/main/release-notes.md).

### Firecracker (escape-hatch references; CVE precedent)

- [Firecracker design.md](https://github.com/firecracker-microvm/firecracker/blob/main/docs/design.md).
- [AWS — "Firecracker open source secure fast microVM serverless"](https://aws.amazon.com/blogs/opensource/firecracker-open-source-secure-fast-microvm-serverless/).
- [Microarchitectural Security of AWS Firecracker VMM (arXiv 2311.15999)](https://arxiv.org/pdf/2311.15999).
- [AWS bulletin 2026-015 — CVE-2026-5747 (virtio-pci OOB write; opt-in `--enable-pci`)](https://aws.amazon.com/security/security-bulletins/2026-015-aws/).
- [AWS bulletin 2026-003 — CVE-2026-1386 (jailer symlink LPE; host-side)](https://aws.amazon.com/security/security-bulletins/rss/2026-003-aws/).
- [edera.dev — "Minimal is no longer enough: why AI-scale vulnerability discovery changes container security"](https://edera.dev/stories/minimal-is-no-longer-enough-why-ai-scale-vulnerability-discovery-changes-container-security).

### Apple `container` (macOS primary)

- [apple/container](https://github.com/apple/container) — upstream repository.
- [Addo Zhang — "Apple container 0.8.0: seven-month evolution from birth to maturity" (Feb 2026)](https://addozhang.medium.com/apple-container-0-8-0-seven-month-evolution-from-birth-to-maturity-1021e570bbb7).
- [InfoQ — "Apple Containerization brings Linux containers to macOS" (Jun 2025)](https://www.infoq.com/news/2025/06/apple-container-linux/).
- [The Register — "Apple Containerization" (Jun 2025)](https://www.theregister.com/2025/06/10/apple_tries_to_contain_itself/).

### gVisor (no-KVM fallback)

- [gvisor.dev — docs](https://gvisor.dev/docs/).
- [gvisor.dev — performance guide](https://gvisor.dev/docs/architecture_guide/performance/).

### Shared-kernel CVE precedent (the "why bare containers are not the boundary" evidence)

- [Sysdig — "runc container escape vulnerabilities" (Nov 2025)](https://www.sysdig.com/blog/runc-container-escape-vulnerabilities) — CVE-2025-31133, CVE-2025-52565, CVE-2025-52881.
- [CNCF — "runc container breakout vulnerabilities: a technical overview" (Nov 2025)](https://www.cncf.io/blog/2025/11/28/runc-container-breakout-vulnerabilities-a-technical-overview/).
- [emirb — "microvm-2026"](https://emirb.github.io/blog/microvm-2026/) — hypervisor-escape bug-class economics.
