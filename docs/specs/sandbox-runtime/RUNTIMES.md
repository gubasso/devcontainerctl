# Sandbox Runtimes — Candidate Catalog

> Status: Draft
> Scope: Per-option evaluation of every sandbox/runtime/VMM considered for `devcontainerctl`.
> Companion: [SPEC.md](./SPEC.md). Reading order: SPEC.md §1 (premises) and §3 (threat model) first, then this catalog.

This document catalogs every sandbox option evaluated for `dctl`, the verdict for each, and the reasoning behind it. The final default backend is **not chosen yet** — see SPEC.md §4 for the current candidate set and the criteria for selection.

## 0. How to read this document

Each entry uses the same shape:

- **What it is** — engine, layer (runtime / VMM / shim), upstream.
- **Security posture** — boundary type (`shared kernel` | `userspace kernel` | `hypervisor`) and CVE evidence relevant to the AI-agent threat model.
- **OCI / devcontainer fit** — does it consume the project's existing OCI images and `devcontainer.json` semantics?
- **Maintenance** — release cadence, project health, corporate backers.
- **What `dctl` would own** — concrete plumbing the project would have to write and maintain.
- **Verdict** — one of:
  - `viable default candidate` — meets the security premise; in scope for the Tier 2 selection.
  - `viable fallback` — meets a degraded scenario (e.g. no-KVM CI runner).
  - `viable controller` — useful as the front-end around a stronger boundary.
  - `defense-in-depth only` — must be applied **inside** a stronger boundary; cannot replace it.
  - `rejected (laptop)` / `rejected (out of scope)` / `rejected (archived)` / `rejected (TCB)` / `rejected (wrong threat model)` — kept here so the rejection reasoning is auditable.
  - `inspirational only` — informs design; not a backend.

Rejection reasoning is required so future revisions can audit whether the constraints have changed.

---

## 1. Rejected — shared-kernel containers as the primary boundary

These options are documented to make the rejection reasoning explicit (SPEC.md §1.5). They are **not** acceptable as the primary sandbox under SPEC.md §3.

### 1.1 Bare Docker (rootful)

- **What it is** — Current `dctl` default. Daemon runs as root; container UID mapped 1:1 to host UID; no userns remap.
- **Security posture** — Shared kernel. Container escape lands as **host root**. Daemon attack surface is itself rooted. Every kernel LPE (bpf, io_uring, netfilter, runc mount-race class) is a host compromise.
- **CVE evidence (recent)** — runc CVE-2025-31133, CVE-2025-52565, CVE-2025-52881 (Nov 2025) all deliver full container breakout via mount races and procfs symlink tricks; CVE-2024-21626 (Leaky Vessels); CVE-2025-9074 (Docker Desktop). [Sysdig analysis](https://www.sysdig.com/blog/runc-container-escape-vulnerabilities); [CNCF technical overview](https://www.cncf.io/blog/2025/11/28/runc-container-breakout-vulnerabilities-a-technical-overview/).
- **OCI fit** — native baseline.
- **Maintenance** — excellent, but irrelevant: the boundary is structurally insufficient for the threat model.
- **Verdict — `rejected`.** Namespaces are a resource-control mechanism, not a security boundary; the 1:1 UID mapping makes escape outcomes worst-case (host root).

### 1.2 Bare Podman (rootful)

- **What it is** — Daemonless OCI runtime; same shared-kernel boundary semantics as rootful Docker.
- **Security posture** — Same shared-kernel reality. Nov 2025 runc CVEs explicitly affect rootful Podman.
- **Verdict — `rejected`.** Removing the daemon eliminates one CVE class but does not change the boundary.

### 1.3 Hardened-container path (seccomp / AppArmor / cap-drop only)

- **What it is** — Strong seccomp profile, AppArmor profile, `cap-drop=ALL`, `no-new-privileges`. The hygiene hardening already enumerated in SPEC.md §5.1 (Tier 0).
- **Security posture** — Defense-in-depth: each layer raises the cost of an exploit but cannot prevent kernel-level LPEs from succeeding.
- **Verdict — `defense-in-depth only`.** Required **inside** the chosen primary boundary, not as a substitute for it.

---

## 2. Reduced-blast-radius containers (better, still insufficient as primary)

### 2.1 Docker rootless

- **What it is** — Daemon runs as user; container UIDs remapped via `/etc/subuid`. [Docker rootless docs](https://docs.docker.com/engine/security/rootless/).
- **Security posture** — Escape lands as **invoking user**, not host root. Same shared kernel; same kernel-LPE class; daemon attack surface still exists, just not as root.
- **OCI fit** — full.
- **Maintenance** — supported upstream, less battle-tested than rootful.
- **Verdict — `defense-in-depth only`.** "Lands as user" still owns the developer's SSH keys, git creds, dotfiles, and probably sudo. Useful as a **controller around a microVM** (see §4.4 libkrun), not as the primary boundary.

### 2.2 Podman rootless

- **What it is** — Daemonless rootless OCI runtime; fork-exec per invocation, no persistent privileged process. [Podman rootless tutorial](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md); [Red Hat: rootless Podman user-namespace modes](https://www.redhat.com/en/blog/rootless-podman-user-namespace-modes); [Docker userns-remap](https://docs.docker.com/engine/security/userns-remap/) for comparison.
- **Security posture** — Best-of-class shared-kernel posture: no daemon, userns by default, slirp4netns/pasta networking. **Still shared kernel** — Nov 2025 runc CVEs apply.
- **OCI fit** — full; the `devcontainer` CLI honors `DOCKER_HOST` pointing at the Podman socket; VS Code Dev Containers exposes `dev.containers.dockerPath: "podman"` ([VS Code + Podman walkthrough](https://blog.okikio.dev/from-docker-to-podman-vs-code-devcontainers)).
- **Maintenance** — active under `containers/` org.
- **Verdict — `defense-in-depth only`** when used as the boundary; **`viable controller`** when paired with a microVM runtime (libkrun via `crun --krun` in §4.4 is the canonical example: Podman is the front-end, the microVM is the boundary).

### 2.3 bubblewrap / Landlock / seccomp-only

- **What it is** — `bwrap` is already used **inside** the agent container by Codex CLI as an inner sandbox. As an outer sandbox: namespaces + seccomp + Landlock LSM.
- **Security posture** — shared kernel; Landlock policy language is still maturing.
- **Verdict — `defense-in-depth only`.** Useful as inner layer, not the primary boundary.

---

## 3. Userspace-kernel sandbox

### 3.1 gVisor (`runsc`)

- **What it is** — Google's userspace kernel. OCI-compliant runtime under containerd. Re-implements ~200 Linux syscalls in memory-safe Go and forwards a tiny subset to the host kernel. [gvisor.dev/docs](https://gvisor.dev/docs/), [performance guide](https://gvisor.dev/docs/architecture_guide/performance/).
- **Security posture** — A *different* boundary: not hardware, not shared-kernel. The host kernel only sees what `runsc` chose to forward, eliminating the kernel-LPE class for unforwarded syscalls. Bugs in `runsc`'s own implementation are still host-side compromises. Used in production by Modal and Cloud Run for untrusted code.
- **Trade-offs** — 10–30% syscall overhead on I/O-heavy workloads; **incomplete syscall coverage** breaks some perf tooling, FUSE, namespacing tricks, exotic ptrace usage.
- **OCI fit** — full; drop-in OCI runtime under containerd.
- **Maintenance** — active, Google-backed.
- **Verdict — `viable fallback`.** The right answer for **no-KVM environments** (CI runners, cloud VMs without nested virt). Not the primary default because hardware isolation is qualitatively stronger for the AI-agent threat model and gVisor's syscall coverage gaps surface as devcontainer breakage.

---

## 4. Hardware-virtualization microVMs — the primary candidate set

These options meet SPEC.md §1.2: a hypervisor-class boundary between agent-executed code and the host kernel. **No final default has been chosen** among them; SPEC.md §4.4 lists the selection criteria.

### 4.1 Bare Firecracker (dctl-owned controller)

- **What it is** — Direct use of the Firecracker VMM with a thin `dctl`-owned controller. Firecracker exposes an HTTP API for boot configuration (kernel, rootfs, vCPU, memory, network). The `jailer` process chroots, applies seccomp, drops privileges, then `exec`s Firecracker — minimizing the host-side attack surface. [Firecracker design doc](https://github.com/firecracker-microvm/firecracker/blob/main/docs/design.md); [AWS open-source announcement](https://aws.amazon.com/blogs/opensource/firecracker-open-source-secure-fast-microvm-serverless/).
- **Security posture** — KVM microVM with a deliberately tiny device model: virtio-net, virtio-blk, serial, partial keyboard controller, KVM-provided interrupt controllers. ~50–83K LoC of Rust. Threat model: every vCPU thread is treated as if it were running malicious code from the moment it starts. **Zero published hypervisor-escape CVEs in 2024–2026**; one jailer host-side LPE. Hypervisor escapes carry $250K–$500K bounty-class economics ([emirb microvm-2026](https://emirb.github.io/blog/microvm-2026/), [stack.watch FC CVEs](https://stack.watch/product/amazon/firecracker/)). [Microarchitectural security analysis (arXiv 2311.15999)](https://arxiv.org/pdf/2311.15999).
- **Performance** — Boots in ~125 ms with <5 MiB overhead per VM; sustains ~150 VMs/s/host (Firecracker NSDI'20).
- **OCI fit** — none directly. Firecracker consumes a kernel image + ext4 rootfs; OCI images must be converted by the controller.
- **Maintenance** — active, AWS-maintained (Lambda + Fargate substrate). [Repository](https://github.com/firecracker-microvm/firecracker).
- **What `dctl` would own:**
  - rootfs builder (skopeo + umoci + mkfs.ext4 + cp -a; ~20 lines bash)
  - TAP device + NAT/route plumbing (~10 lines `ip`)
  - in-guest init (mount /proc, eth0, vsock listener, exec agent)
  - controller via [firecracker-go-sdk](https://github.com/firecracker-microvm/firecracker-go-sdk) or [firepilot](https://github.com/rik-org/firepilot) (~500 LOC helper binary)
  - vsock-based exec channel (`socat` or small helper)
  - replacement for `devcontainer up` — VS Code's CLI does not drive FC
  - kernel image lifecycle (updates, signing)
- **Cost estimate** — ~3–5 calendar weeks one-time + ongoing maintenance of rootfs builder, kernel updates, in-guest agent.
- **Public precedent** — [firedocker](https://github.com/magmastonealex/firedocker), firebuild, [buildfs (crates.io)](https://crates.io/crates/buildfs), [iximiuz Firecracker hands-on](https://labs.iximiuz.com/courses/firecracker-hands-on/run-first-microvm), [single-app rootfs cookbook](https://blog.cloudkernels.net/posts/fc-rootfs/), [firectl](https://github.com/firecracker-microvm/firectl), archived [Ignite](https://github.com/weaveworks/ignite) reference recipes.
- **Verdict — `viable default candidate`** (high-assurance / power-user path). Smallest TCB of any option, lowest supply-chain risk, highest implementation cost. Worth keeping as a documented escape hatch even if not the default.

### 4.2 Firecracker via Kata Containers

- **What it is** — Kata Containers (OCI-compliant runtime, containerd shim, kata-agent inside the guest) using Firecracker as the underlying VMM. [Kata Containers](https://katacontainers.io/); [Kata + Firecracker how-to](https://github.com/kata-containers/kata-containers/blob/main/docs/how-to/how-to-use-kata-containers-with-firecracker.md); [Kata releases](https://github.com/kata-containers/kata-containers/releases).
- **Security posture** — Same Firecracker boundary as §4.1, plus Kata's containerd shim and the kata-agent inside the guest. Hypervisor boundary; small TCB on the VMM side, larger TCB on the runtime side.
- **OCI fit** — full; `nerdctl --runtime io.containerd.kata.v2`.
- **Maintenance — Kata project** — CNCF incubating ([October 2025 PTG update](https://katacontainers.io/blog/kata-community-ptg-updates-october-2025/)). ~3-week release cadence (3.23.0 → 3.30.0 in 6 months as of May 2026). ~1,515 open / ~4,451 closed issues; lifetime closure rate ~75%; net-deflating in trailing 12 months (closes 1.6× the open rate). Cross-vendor maintainers (Intel, Red Hat, Microsoft, IBM, Alibaba). Production users include Baidu, Alibaba, AWS, Northflank.
- **Maintenance — Kata-on-FC specifically** — second-class within Kata. Firecracker has **no virtio-fs**, so Kata-on-FC requires the **devmapper snapshotter** with a block device per container, losing the bind-mount UX virtio-fs gives Kata-on-QEMU/CH. 66 open Kata issues mention Firecracker; e.g. [#12558](https://github.com/kata-containers/kata-containers/issues/12558), [#8843](https://github.com/kata-containers/kata-containers/issues/8843), [#13008](https://github.com/kata-containers/kata-containers/issues/13008).
- **What `dctl` would own** — runtime-class registration in containerd, devmapper setup, host KVM detection. Kernel image, rootfs builder, in-guest agent are upstream.
- **Verdict — `viable default candidate`.** Strong security; substantial operational friction from the devmapper + containerd + Kata stack on a developer laptop.

### 4.3 Cloud Hypervisor via Kata Containers

- **What it is** — Kata with [Cloud Hypervisor](https://github.com/cloud-hypervisor/cloud-hypervisor) as the VMM. CH is a Rust user-space VMM over KVM, sibling to Firecracker, sharing rust-vmm crates.
- **Security posture vs FC** — Same KVM boundary class. Larger device surface in default config: ~106K LoC vs FC's ~50–83K; supports virtio-fs, virtio-mem, virtio-vsock, PCI hotplug, VFIO, vhost-user, GPU passthrough, nested KVM. Trimmable via build/feature flags. Adds Landlock-based host-side sandboxing ([CH landlock.md](https://github.com/cloud-hypervisor/cloud-hypervisor/blob/main/docs/landlock.md)). Zero published hypervisor-escape CVEs 2024–2026 ([CH release notes](https://github.com/cloud-hypervisor/cloud-hypervisor/blob/main/release-notes.md)).
- **Net assessment** — Equivalent to FC in **kind** (KVM, user-space VMM, rust-vmm primitives). Slightly worse in default device **surface**; Landlock partly compensates. Not a security upgrade over FC; not a security regression over FC. The choice between them collapses to operational fit, not threat-model strength.
- **OCI fit** — full via Kata.
- **Maintenance** — very active (v50/v51 in Feb 2026); ~5,612 stars; Intel/Microsoft-led.
- **Practical edge over Kata-on-FC** — virtio-fs (no devmapper snapshotter required), nested KVM (DinD works), GPU passthrough. The path the Kata community actually exercises in production ([Northflank: Kata vs Firecracker vs gVisor](https://northflank.com/blog/kata-containers-vs-firecracker-vs-gvisor); [AWS: enhancing Kubernetes workload isolation with Kata](https://aws.amazon.com/blogs/containers/enhancing-kubernetes-workload-isolation-and-security-using-kata-containers/)).
- **Verdict — `viable default candidate`.** Kept on the table per the project's reframe (FC-like options are explicitly in scope). Operationally smoother than Kata-on-FC; identical security class.

### 4.4 libkrun via `crun --krun` (Podman-rootless front-end)

- **What it is** — Rust VMM under [containers/libkrun](https://github.com/containers/libkrun) (v1.18.0, 2026-04-24). Code partly **derived from Firecracker, Cloud Hypervisor, and rust-vmm**. Integrates with `crun` via `crun --krun`, which is a Podman-native OCI runtime. [Red Hat: RamaLama + libkrun (Jul 2025)](https://developers.redhat.com/articles/2025/07/02/supercharging-ai-isolation-microvms-ramalama-libkrun); [containers/krunvm](https://github.com/containers/krunvm).
- **Security posture** — KVM microVM; same hardware-isolation class as FC. Maintainer's threat model ([libkrun #538](https://github.com/containers/libkrun/discussions/538)): "the guest and the VMM pertain to the same security context… should be thought of as a single entity." `crun --krun` wraps the microVM in Podman-rootless's userns + seccomp envelope, providing the host-side containment FC's `jailer` provides standalone.
- **OCI fit** — full. `podman --runtime krun run <image>` consumes OCI images directly; rootfs conversion is internal to `crun-krun`. No bespoke builder.
- **Networking** — TSI (Transparent Socket Impersonation) eliminates TAP/bridge plumbing.
- **Maintenance** — active under `containers/` org (same org as Podman, crun, Buildah). Powers Microsandbox, RamaLama, krunvm.
- **Cross-platform** — Linux KVM and macOS HVF (Hypervisor.framework) backends.
- **What `dctl` would own** — a `runtime/krun.sh` adapter that adds `--runtime krun` to existing Podman calls. Rootfs conversion, kernel image, in-guest agent are all upstream.
- **Verdict — `viable default candidate`** (lowest plumbing cost). Equivalent security boundary to FC with the smallest implementation footprint among hardware-virt options. Trade-off: more upstream code on the trust path than bare-FC.

### 4.5 QEMU `microvm` machine type

- **What it is** — QEMU's stripped-down machine type optimized for microVM workloads. Same KVM boundary as §4.1–§4.4.
- **Security posture** — Same KVM boundary class, but TCB is ~1.4M LoC of C with a multi-decade device-emulation CVE history ([Northflank: Firecracker vs QEMU](https://northflank.com/blog/firecracker-vs-qemu)).
- **Verdict — `rejected (TCB)`** as the laptop default. Same boundary class, much larger TCB. No security gain and a real loss vs FC/CH/libkrun. Useful only when a user explicitly needs a feature only QEMU provides (e.g. exotic device passthrough).

### 4.6 Apple `container` (macOS)

- **What it is** — Swift, open-source, [`apple/container`](https://github.com/apple/container) (macOS 26+). One lightweight VM per Linux container via Virtualization.framework. Sub-second cold start. [InfoQ coverage](https://www.infoq.com/news/2025/06/apple-container-linux/); [The Register: Apple Containerization](https://www.theregister.com/2025/06/10/apple_tries_to_contain_itself/).
- **Security posture** — Hypervisor boundary via Apple's Virtualization.framework / Hypervisor.framework. Not Firecracker, but the same architectural class on Apple silicon. Effectively "FC-for-Mac."
- **OCI fit** — full; `container run`-style CLI.
- **Maintenance** — Apple-backed; macOS 26+ only.
- **Verdict — `viable default candidate (macOS)`.** Pairs with libkrun/Kata as the Linux-side equivalent. **Open question:** does libkrun's macOS HVF backend reach feature parity, or do we keep Apple `container` as the Mac-native path?

---

## 5. Specialized / wrong-shaped at this layer

### 5.1 firecracker-containerd

- **What it is** — containerd shim + snapshotter for Firecracker. AWS-maintained; no GitHub releases ever cut; commits active. [firecracker-containerd snapshotter docs](https://github.com/firecracker-microvm/firecracker-containerd/blob/main/docs/snapshotter.md).
- **Verdict — `rejected (laptop)`.** Cluster/operator-shaped, no per-developer ergonomics story. Useful component, wrong layer for `dctl`.

### 5.2 flintlock

- **What it is** — Cluster-scale microVM lifecycle manager. v0.9.1 released 2025-11-19 under `liquidmetal-dev` (post-Weaveworks). [Repository](https://github.com/liquidmetal-dev/flintlock).
- **Verdict — `rejected (laptop)`.** Cluster-shaped. Not a per-developer tool.

### 5.3 Ignite (Weaveworks)

- **What it is** — Weaveworks' Firecracker-as-Docker-CLI tool. Archived in 2023. [Repository (archived)](https://github.com/weaveworks/ignite).
- **Verdict — `rejected (archived)`.** Reference recipes still useful for the bare-FC path (§4.1).

### 5.4 SUSE flake-pilot / firecracker-pilot

- **What it is** — [OSInside/flake-pilot](https://github.com/OSInside/flake-pilot). App launcher: symlink → launcher → podman or Firecracker backend. [SUSE Package Hub](https://packagehub.suse.com/packages/flake-pilot/).
- **Why considered** — The project ships an openSUSE-based image, so SUSE-aligned tooling is a natural fit candidate.
- **Why it doesn't fit** — The Firecracker backend uses **kernel + rootfs tarballs from HTTPS**, not OCI registries. It bypasses the entire Dockerfile / devcontainer build flow `dctl` is built around. Tiny project (~8 stars), DIY networking (manual TAP, kernel msgs leak into stdout). The OCI image flow would have to be re-implemented anyway.
- **Verdict — `inspirational only`.** A useful example of a thin SUSE-native FC wrapper; not a backend `dctl` should adopt.

### 5.5 Hyperlight (Microsoft)

- **What it is** — CNCF Sandbox 2025; embeddable Rust VMM with **no kernel, no OS in the guest**. ~1ms startup. [Microsoft introduction (Nov 2024)](https://opensource.microsoft.com/blog/2024/11/07/introducing-hyperlight-virtual-machine-based-security-for-functions-at-scale/).
- **Verdict — `rejected (out of scope)`.** Designed for WebAssembly modules and individual function calls. Cannot host `python`, `cargo`, `git`, or a developer's full toolchain. Wrong shape for AI-agent workloads.

### 5.6 Confidential Containers / Kata-CoCo (TDX / SEV-SNP)

- **What it is** — Kata variant designed against a *malicious host* (untrusted cloud operator). Hardware-attested isolation.
- **Verdict — `rejected (wrong threat model)`.** SPEC.md §3 trusts the host (the developer's laptop) and distrusts the workload. CoCo solves the inverse problem (trusted workload, untrusted host).

### 5.7 V8 isolates / WebAssembly sandboxes

- **What it is** — Process-internal language sandboxes.
- **Verdict — `rejected (out of scope)`.** Cannot run `pytest`, `cargo build`, native dependency builds, or the agent's full toolchain.

### 5.8 youki + Firecracker hooks

- **What it is** — youki is a Rust OCI runtime ([youki-dev/youki](https://github.com/youki-dev/youki), 7.4k stars).
- **Verdict — `rejected (no FC integration today)`.** youki itself is healthy, but does not ship a Firecracker integration. Not a Firecracker-composing path in 2026.

### 5.9 AWS firecracker-task-driver / Nomad

- **What it is** — Nomad's Firecracker driver for cluster scheduling.
- **Verdict — `rejected (cluster only)`.** Wrong shape for a developer-laptop CLI.

---

## 6. Comparison matrix

| Option | Boundary | OCI fit | `dctl` owns | Maintenance | Verdict |
|---|---|---|---|---|---|
| Bare Docker (rootful) | shared kernel | full | nothing | excellent | rejected |
| Bare Podman (rootful) | shared kernel | full | nothing | excellent | rejected |
| Hardened-container path | shared kernel + LSMs | n/a | profile maintenance | n/a | DiD only |
| Docker rootless | shared kernel + userns | full | nothing | good | DiD only |
| Podman rootless | shared kernel + userns | full | nothing | excellent | DiD only / viable controller |
| bwrap / Landlock | shared kernel | n/a | inner profile | active | DiD only |
| gVisor | userspace kernel | full | nothing | active (Google) | viable fallback (no-KVM) |
| Bare Firecracker | hypervisor (KVM) | none → built | rootfs builder, controller, init, kernel, vsock exec | active (AWS) | viable default candidate |
| Kata + Firecracker | hypervisor (KVM) | full | runtime-class, devmapper | active (CNCF incubating) | viable default candidate |
| Kata + Cloud Hypervisor | hypervisor (KVM) | full | runtime-class | active | viable default candidate |
| libkrun + `crun --krun` | hypervisor (KVM) | full | adapter + flag | active (containers/) | viable default candidate |
| QEMU microvm | hypervisor (KVM) | via Kata | similar to Kata | excellent but huge TCB | rejected (TCB) |
| Apple `container` | hypervisor (HVF) | full | macOS adapter | active (Apple) | viable default candidate (macOS) |
| firecracker-containerd | hypervisor (KVM) | partial | cluster integration | active (AWS) | rejected (cluster) |
| flintlock | hypervisor (KVM) | partial | cluster integration | active (liquidmetal-dev) | rejected (cluster) |
| Ignite | hypervisor (KVM) | partial | n/a | archived | rejected (archived) |
| flake-pilot / firecracker-pilot | hypervisor (KVM) | none | OCI flow + plumbing | small, niche | inspirational only |
| Hyperlight | hypervisor (KVM) | none | n/a | active (Microsoft) | rejected (cannot host toolchain) |
| Confidential Containers | hypervisor + attest | full | Kata + attestation | active | rejected (wrong threat model) |
| V8 / WebAssembly | language sandbox | none | n/a | n/a | rejected (cannot run toolchain) |
| youki + FC hooks | n/a | full | FC integration absent | active | rejected (no FC path) |
| AWS Nomad FC driver | hypervisor (KVM) | partial | cluster integration | active | rejected (cluster) |

---

## 7. References

Cited inline; the consolidated list also lives in SPEC.md §9.
