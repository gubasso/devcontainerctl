# Sandbox Runtime — libkrun vs. flake-pilot + Firecracker

> Status: Informational comparison
> Date: 2026-05-11
> Scope: Technical comparison between the sandbox runtime decision recorded in [DECISION-LINUX.md](./DECISION-LINUX.md) — libkrun via `crun --krun` fronted by Podman-rootless — and an alternative stack built on [OSInside/flake-pilot](https://github.com/OSInside/flake-pilot)'s firecracker-pilot backend over bare [Firecracker](https://firecracker-microvm.github.io/) microVMs.
> Companions: [DECISION-LINUX.md](./DECISION-LINUX.md), [DECISION.md](./DECISION.md), [RUNTIMES.md](./RUNTIMES.md) (§5.4 documents flake-pilot in the catalog), [SPEC.md](./SPEC.md).

## 0. Summary

| Approach | Boundary class | Authoring surface | Networking | Privilege model | Project maturity |
|---|---|---|---|---|---|
| **libkrun via `crun --krun` + Podman-rootless** | **KVM microVM** | **OCI / devcontainer schema** | TSI (no host TAP/bridge) | Rootless | `containers/` org; production users (RamaLama, Microsandbox, krunvm) |
| **flake-pilot (`firecracker-pilot`) + Firecracker** | **KVM microVM** | KIWI KIS tarballs over HTTPS + flake YAML | Manual TAP + iptables + NAT | `sudo` per invocation | Firecracker is mature (powers AWS Lambda / Fargate). flake-pilot is a registration/provisioning framework with multiple backend pilots (`podman-pilot`, `firecracker-pilot`); this comparison evaluates the `firecracker-pilot` path. |

**Both approaches sit in the same KVM hardware-virtualization isolation class.** Neither shares the host kernel with the guest; both rely on KVM as the security boundary. The framing that "VMs are the only safe option to shield host data" applies equally to either — collapsing the question to *which* microVM stack, not *whether* to use one.

Throughout this document, **libkrun** refers to the runtime stack selected in [DECISION-LINUX.md](./DECISION-LINUX.md) — libkrun via `crun --krun` fronted by Podman-rootless. Relative to the goals stated in [DECISION-LINUX.md §1](./DECISION-LINUX.md), flake-pilot + Firecracker does not present an advantage on the boundary axis; it loses on engineering cost, networking simplicity, privilege model, authoring surface, and image distribution model. [RUNTIMES.md §5.4](./RUNTIMES.md) catalogs flake-pilot for reference; this document spells out the technical reasoning at finer granularity.

---

## 1. The two approaches

### 1.1 libkrun via `crun --krun` + Podman-rootless

See [DECISION-LINUX.md §2](./DECISION-LINUX.md) for the full rationale.

Architecture in one paragraph: [`containers/libkrun`](https://github.com/containers/libkrun) is a Rust user-space VMM (rust-vmm lineage, partly derived from Firecracker and Cloud Hypervisor). Passing `--krun` to [`crun`](https://github.com/containers/crun) boots the OCI bundle inside a libkrun microVM instead of a namespaces-only container; Podman drives it as a normal OCI runtime: `podman --runtime krun run <image>`. Networking is **TSI (Transparent Socket Impersonation)** — in-guest sockets are transparently forwarded to host sockets through libkrun, with no TAP device, bridge, NAT, or `slirp4netns` plumbing on the host side.

Invocation surface for the user: `dctl ws up` → adapter sets `--runtime krun` on the existing rootless Podman invocation. No additional config required; existing OCI artifacts under `images/` are consumed unchanged.

### 1.2 flake-pilot + Firecracker

[`OSInside/flake-pilot`](https://github.com/OSInside/flake-pilot) is a registration/provisioning framework for running applications inside isolated environments. It ships multiple backend "pilots"; per the upstream README, *"as of today, support for the `podman` and `firecracker` engines is implemented, leading to the respective `podman-pilot` and `firecracker-pilot` launcher binaries."* The framework's primary contribution is enabling semi-transparent container/VM instances that can run provisioning steps before execution. **This comparison evaluates the `firecracker-pilot` backend specifically** — that is the path the alternative proposal exercises. Images for the Firecracker path are [KIWI](https://osinside.github.io/kiwi/)-built **KIS** artifacts (kernel + initrd + rootfs tarball) distributed over HTTPS, not OCI registries. Packaging is primarily through openSUSE repositories; the source is Rust and can be built on other distributions from source.

Reference invocation (as documented upstream):

```text
sudo flake-ctl firecracker pull \
    --name <name> \
    --kis-image <https-url>/<image>.x86_64-<version>.tar.xz

sudo flake-ctl firecracker register \
    --vm <name> \
    --app /usr/bin/<launcher-name> \
    --target /bin/bash \
    --overlay-size 20GiB \
    --force-vsock \
    --resume

sudo <launcher-name>
```

Networking is **deferred to manual TAP + iptables + NAT setup** by the host operator, per the upstream README's [networking section](https://github.com/OSInside/flake-pilot#networking-): *"it is the user's responsibility to set up the routing on the host from the TUN/TAP device to the outside world."*

---

## 2. Isolation / threat model

| Axis | libkrun | flake-pilot + Firecracker |
|---|---|---|
| Kernel sharing host ↔ guest | **None.** libkrun is a user-space VMM over KVM; guest runs its own kernel. ([RUNTIMES.md §4.4](./RUNTIMES.md)) | **None.** Guest runs its own kernel under KVM via Firecracker. ([Firecracker design.md](https://github.com/firecracker-microvm/firecracker/blob/main/docs/design.md)) |
| Boundary class | KVM microVM. | KVM microVM. **Same class.** |
| Container-escape attack surface (runc, namespaces) | **Eliminated at the primary boundary.** libkrun does not use shared-kernel namespaces as the boundary. The Nov 2025 runc CVE cluster ([Sysdig](https://www.sysdig.com/blog/runc-container-escape-vulnerabilities), [CNCF](https://www.cncf.io/blog/2025/11/28/runc-container-breakout-vulnerabilities-a-technical-overview/)) does not apply. Podman-rootless is layered as defense-in-depth on the *host-side* control surface, not as the boundary itself. | Eliminated — no container runtime in the path. |
| Hypervisor-escape risk | KVM + libkrun. No published hypervisor-escape CVEs in libkrun 2024–2026 ([DECISION-LINUX.md §2.2](./DECISION-LINUX.md)). Shared `rust-vmm` lineage with Firecracker and Cloud Hypervisor means a class bug in shared crates lands on all three simultaneously ([RUNTIMES.md §4.4](./RUNTIMES.md)). | KVM + Firecracker. Zero published *guest-escape* CVEs 2024–2026 ([RUNTIMES.md §4.1](./RUNTIMES.md)). [CVE-2026-5747](https://aws.amazon.com/security/security-bulletins/2026-015-aws/) affects only the opt-in `--enable-pci` flag (default MMIO unaffected); [CVE-2026-1386](https://aws.amazon.com/security/security-bulletins/rss/2026-003-aws/) is a host-side `jailer` symlink LPE, not a guest escape. |
| Host-side VMM TCB | libkrun + crun + Podman-rootless. Larger than `firecracker` + `jailer` in line count, but every component is from the [`containers/`](https://github.com/containers) org and audited as part of the OCI ecosystem. | `firecracker` + `jailer` is the smallest VMM TCB in the candidate set ([arXiv 2311.15999](https://arxiv.org/pdf/2311.15999)), plus the `firecracker-pilot` launcher binary and the flake-pilot registration tooling. The smaller VMM TCB is real but does **not** raise the isolation class above what libkrun already provides. |
| Device / IO surface | Minimal virtio set inside the guest; TSI removes host-side TAP/bridge/NAT entirely. ([RUNTIMES.md §4.4](./RUNTIMES.md)) | Firecracker exposes exactly five guest devices: virtio-net, virtio-block, virtio-vsock, serial console, minimal i8042. USB, GPU passthrough, and full virtio set are intentionally not supported ([Firecracker design.md](https://github.com/firecracker-microvm/firecracker/blob/main/docs/design.md)). **No virtio-fs in stable releases** ([upstream issue #1180](https://github.com/firecracker-microvm/firecracker/issues/1180), rejected for attack-surface reasons; see also the rejected WIP [PR #1351](https://github.com/firecracker-microvm/firecracker/pull/1351)). |
| Host-side network attack surface | **TSI eliminates host TAP/bridge/NAT.** No privileged-network plumbing on the host. ([DECISION.md §2.1](./DECISION.md)) | **Manual TAP + iptables + NAT required on the host** ([flake-pilot README — networking](https://github.com/OSInside/flake-pilot#networking-)). Every operator must own and audit the host-side filtering chain. Firecracker upstream explicitly states it does not filter guest traffic: *"All egress traffic from a guest is therefore considered untrusted, and should be filtered at the host-level"* ([prod-host-setup.md](https://github.com/firecracker-microvm/firecracker/blob/main/docs/prod-host-setup.md), [network-setup.md](https://github.com/firecracker-microvm/firecracker/blob/main/docs/network-setup.md)). |
| Egress policy enforcement | Tier-0 mandates an egress allowlist by default at the `dctl`-managed nftables/userspace-proxy level ([SPEC.md §5.2](./SPEC.md), [SPEC.md §6 T0](./SPEC.md)). Runtime-agnostic and **shipped by `dctl`**. | flake-pilot ships no egress policy. All host `nft`/`iptables` work is operator-owned. |
| Credential / token leakage to host | Tier-0 replaces host-config bind-mounts (`~/.config/gh`, `~/.config/glab-cli`, `~/.claude*`) with scoped, ephemeral token forwarding ([SPEC.md §5.2](./SPEC.md)); drops host `/tmp` bind; `no-new-privileges`; `cap-drop=ALL`. Runtime-agnostic. | No bind-mounts at all (Firecracker has no virtio-fs in stable). Structurally more isolating on the file-sharing axis, but the practical implication is that the operator must invent a sync mechanism (whole-rootfs overlay, vsock-based tool, image rebuild) to get project artifacts in or out. See §4. |
| Privilege model | **Rootless.** `dctl ws up` runs as the invoking user; Podman-rootless under the hood. ([DECISION.md §2.2](./DECISION.md)) | **`sudo` on every invocation.** `sudo flake-ctl firecracker pull/register` and `sudo <launcher>`. Firecracker's `jailer` drops privileges inside the launched VM, but the host-side user-facing UX is `sudo` per call. |

**Honest assessment of the "VMs are the only safe option to shield host data" framing.** The claim is technically correct **as a comparison against shared-kernel containers** — KVM-class isolation is qualitatively stronger than namespaces + seccomp + AppArmor + userns, and the Nov 2025 runc CVE cluster is the canonical recent precedent. This premise is already encoded in the project's premises: see [SPEC.md §1](./SPEC.md) — *"hardware-virtualization boundary against adversarial code."* libkrun and the flake-pilot proposal **both** satisfy that premise. The claim therefore collapses to a choice **between two KVM stacks**, not between "VM" and "container." Interpreted as "Firecracker specifically is the only safe option," the framing is overstated: libkrun delivers the same boundary class with a far smaller `dctl`-owned plumbing surface and the same KVM-level guest kernel isolation.

---

## 3. Cost / performance

| Axis | libkrun | flake-pilot + Firecracker |
|---|---|---|
| Cold start | libkrun adds minimal overhead on top of `podman run`. Underlying VMM boot is in the Firecracker class (~125 ms boot, <5 MiB VMM overhead per [firecracker-microvm.github.io](https://firecracker-microvm.github.io/)). | ~125 ms FC boot **plus** KIS tarball pull from HTTPS **plus** overlay setup on first registration. `--resume` keeps a warm VM. ([RUNTIMES.md §5.4](./RUNTIMES.md)) |
| Memory baseline per instance | One guest kernel + minimal rootfs per microVM, plus libkrun overhead. | One guest kernel + KIS rootfs per VM. `--overlay-size 20GiB` is **disk allocation**, not RAM. |
| Disk footprint | libkrun reuses Podman's image store directly via OCI layers ([DECISION.md §2.2](./DECISION.md)). Layers are shared across containers built from the same base image. | Each registered VM gets its own overlay (20 GiB in the upstream demo). **No layer sharing** across registrations. KIS artifacts are full kernel + initrd + rootfs tarballs distributed via HTTPS, not OCI registries ([RUNTIMES.md §5.4](./RUNTIMES.md)). |
| Image distribution model | **OCI registries** — same as the rest of the ecosystem. Reuses existing `dctl images push/pull` and any registry the project already operates. Compatible with cosign / sigstore / digest pinning. | **HTTPS file servers** distributing KIS tarballs. No registry-level features (digest pinning at registry layer, mirroring, OCI-compatible signing). |
| Iteration loop cost | Sub-second on a warm system; adapter is ~80–150 LOC bash. | Acceptable for one long-lived warm VM via `--resume`; expensive for many short-lived experiments because every VM is a full kernel boot + rootfs overlay and there is no container-grade image-layer cache. |
| Density | Bounded by the same KVM/memory limits as any microVM stack. | Same KVM/memory limits; lower disk density because no layer sharing. |

---

## 4. Operational model and authoring surface

This is the axis on which the two approaches differ most.

| Axis | libkrun | flake-pilot + Firecracker |
|---|---|---|
| File sharing host ↔ guest | **virtiofs-class sharing** through `crun --krun` integration with Podman's mount machinery ([DECISION.md §2.2](./DECISION.md)). Workspace mounts behave like Podman bind-mounts from the user's perspective. Tier-0 explicitly drops the host `/tmp` bind ([SPEC.md §5.2](./SPEC.md)). | **No virtio-fs in stable Firecracker.** Only virtio-blk and vsock. The upstream demo uses `--force-vsock`. To project a working set into the guest, the operator must (a) bake artifacts into the rootfs (not iterative), (b) treat the rootfs as a 20 GiB overlay accessed via ssh-over-vsock, or (c) build a vsock-based sync tool. Sources: [firecracker-microvm.github.io](https://firecracker-microvm.github.io/), [issue #1180](https://github.com/firecracker-microvm/firecracker/issues/1180). |
| Host networking plumbing | **None on the host.** TSI handles socket forwarding inside libkrun. | **Operator-owned.** Manual TAP + iptables + IP-forwarding + NAT; no DHCP without pre-existing routing; auto-TAP-create races possible. ([flake-pilot README — networking](https://github.com/OSInside/flake-pilot#networking-)) |
| Privilege escalation per invocation | None — rootless. | `sudo` per invocation. |
| Image authoring | OCI / Containerfile schema preserved. The composition system in `schemas/compose.schema.yaml` keeps working. `dctl` image build pipeline is reused. | KIWI XML build descriptions plus a flake YAML. Replaces the OCI/Containerfile authoring surface entirely; no path to consume existing `images/` artifacts unchanged. |
| Adapter implementation cost owned by `dctl` | `lib/dctl/runtime/krun.sh` ~80–150 LOC bash, adding `--runtime krun` to existing Podman calls. ([DECISION.md §2.2](./DECISION.md)) | To reach parity with the libkrun `dctl ws up` UX, `dctl` would also have to own the KIS image pipeline (or replace it with an OCI-to-rootfs converter), the host networking setup, and a `dctl`-side adapter calling out to `flake-ctl firecracker` / the `firecracker-pilot` launcher. Bare-Firecracker plumbing cost is documented at ~3–5 calendar weeks one-time plus a permanent maintenance tail ([DECISION.md §2.5](./DECISION.md)); flake-pilot's `firecracker-pilot` covers some of that orchestration but does not eliminate the rootfs/distribution/networking pieces. |

Note on the authoring/IDE relationship: the OCI / `devcontainer.json` authoring surface is preserved by the libkrun stack because it reuses `dctl`'s existing image pipeline. Editor or IDE integration is **not a goal of the decided runtime** (see [DECISION-LINUX.md §1](./DECISION-LINUX.md)); the OCI compatibility matters here for the **build and distribution** model, not for IDE support.

---

## 5. Maturity and ecosystem

| Axis | libkrun | flake-pilot + Firecracker |
|---|---|---|
| Upstream project maturity | libkrun is under [`containers/`](https://github.com/containers/libkrun) — same org as Podman, crun, Buildah, Skopeo. v1.18.0 shipped 2026-04-24. Active commit cadence. | Firecracker is mature and widely deployed (powers AWS Lambda and Fargate). flake-pilot is a registration/provisioning framework with multiple backend pilots (`podman-pilot`, `firecracker-pilot`); the `firecracker-pilot` binary is what sits in `dctl`'s trust path if adopted along the Firecracker path. Packaging is primarily via openSUSE repositories; source builds work elsewhere. |
| Production proof | **RamaLama** (Red Hat's primary AI-isolation product for local model execution; [Red Hat Developer, Jul 2025](https://developers.redhat.com/articles/2025/07/02/supercharging-ai-isolation-microvms-ramalama-libkrun)); **Microsandbox**; **krunvm**. | Firecracker is production-proven at scale ([Northflank — What is AWS Firecracker](https://northflank.com/blog/what-is-aws-firecracker)). The `firecracker-pilot` component of flake-pilot does not have comparable public production-deployment evidence outside the upstream demos. |
| Distro packaging | libkrun packaged across Fedora, openSUSE, Arch, Debian, Ubuntu via the [`containers/`](https://github.com/containers) org. CVE pipeline runs through standard distro security channels (see e.g. [FEDORA-2025-f8be7978e3](https://linuxsecurity.com/advisories/fedora/fedora-41-libkrun-2025-f8be7978e3-security-advisory-updates-rh8lbifoalx6)). | Packaged primarily for openSUSE ([SUSE PackageHub — flake-pilot](https://packagehub.suse.com/packages/flake-pilot/)); elsewhere requires building from source. |
| Image artifact ecosystem | OCI: registries, signing (cosign/sigstore), digest pinning, the entire OCI ecosystem. | KIS tarballs over HTTPS. No OCI registry semantics; signing/verification is operator-owned. |
| Networking story | TSI: zero host-side plumbing required. ([DECISION.md §2.1](./DECISION.md)) | Manual TAP + iptables + IP-forwarding + NAT per host. ([flake-pilot README — networking](https://github.com/OSInside/flake-pilot#networking-)) |

---

## 6. Fit to the goals stated in DECISION-LINUX.md

[DECISION-LINUX.md §1](./DECISION-LINUX.md) sets the decision criteria. The colour-coded scorecard:

| Criterion | libkrun | flake-pilot + Firecracker |
|---|---|---|
| 1. Security via KVM-class hardware-virt boundary | ✅ Met. KVM microVM. | ✅ Met. KVM microVM. **No delta.** |
| 2. Production-proven, well-maintained | ✅ `containers/` org; RamaLama / Microsandbox / krunvm in production. | ⚠️ Firecracker is production-proven; the `firecracker-pilot` binary that sits in `dctl`'s trust path on the Firecracker path does not have comparable public production-deployment evidence. |
| 3. Clean UX, minimal owned plumbing | ✅ ~80–150 LOC adapter; OCI-native; rootless; TSI removes host networking plumbing entirely. | ❌ Manual TAP + iptables, `sudo` per call, no OCI compatibility, operator-owned image distribution via HTTPS. |
| 4. Single working Linux implementation | ✅ One adapter, one manifest value. | ⚠️ Single Linux implementation in principle, but feature parity with the libkrun stack requires `dctl` to re-implement the OCI build/distribution pipeline against KIS images, plus own the host networking story. |
| 5. Migration cheap | ✅ Adapter is small; behind the runtime interface a future swap is mechanical. | ⚠️ Adopting flake-pilot now means moving the authoring surface off OCI; that is a deep migration and the inverse direction from the decided libkrun stack. |

[RUNTIMES.md §5.4](./RUNTIMES.md) catalogs flake-pilot and notes the same architectural drivers visible here: the OCI-incompatible image flow on the Firecracker path, the operator-owned host networking, and a `firecracker-pilot` launcher binary that would land in `dctl`'s trust path.

---

## 7. Verdict

### 7.1 Where libkrun wins

- **Engineering cost.** ~80–150 LOC adapter vs. the rootfs/kernel/init/vsock/TAP plumbing project that the flake-pilot path would require `dctl` to own to reach feature parity. ([DECISION-LINUX.md §2.2](./DECISION-LINUX.md))
- **Host-side networking attack surface.** TSI removes host TAP/bridge/NAT; flake-pilot requires the operator to construct and maintain that chain. ([DECISION.md §2.1](./DECISION.md), [flake-pilot README — networking](https://github.com/OSInside/flake-pilot#networking-))
- **Privilege model.** Rootless invocation vs. `sudo` per invocation.
- **Image authoring and distribution.** OCI registries with `dctl`'s existing build pipeline vs. KIS tarballs over HTTPS distributed by operator-run file servers; signing and digest pinning come for free with OCI.
- **Egress policy enforcement.** Tier-0 egress allowlist shipped by `dctl` (runtime-agnostic) vs. operator-owned manual filtering.
- **Production-proven upstream.** `containers/` org with RamaLama / Microsandbox / krunvm in production. Firecracker itself is production-proven at AWS scale, but the `firecracker-pilot` launcher binary that would sit in `dctl`'s trust path does not have comparable public production-deployment evidence.
- **Maintenance posture.** Distro-packaged CVE pipeline across the major Linux distributions vs. SUSE-aligned packaging and a thin wrapper to track.

### 7.2 Scenarios excluded from this comparison

Two scenarios sometimes cited as advantageous for flake-pilot + Firecracker are **out of scope** for this comparison because they do not correspond to the goals stated in [DECISION-LINUX.md](./DECISION-LINUX.md):

- **"Smallest possible host-side VMM TCB"** is not a selection criterion in [DECISION-LINUX.md](./DECISION-LINUX.md). The security premise there is the **boundary class** (KVM hardware-virtualization), which is satisfied identically by libkrun and bare Firecracker. A smaller VMM TCB tightens the host trust path but does not raise the isolation class. If a future deployment ever requires the smallest possible VMM TCB on the host, the bare-Firecracker adapter slot remains documented in [DECISION.md §2.5](./DECISION.md) for opt-in — but it is catalog-only and not part of the decided implementation.
- **"Distribution-specific (e.g. openSUSE-only) deployments"** is not a selection criterion in [DECISION-LINUX.md](./DECISION-LINUX.md). The decided implementation targets KVM-capable Linux broadly; distribution coverage is met by libkrun's `containers/`-org packaging across Fedora, openSUSE, Arch, Debian, and Ubuntu. A distribution-aligned packaging story is a distribution preference, not a security or correctness property that would tilt the decision.

### 7.3 Where flake-pilot + Firecracker does not present a relevant win

Outside of the two excluded scenarios in §7.2, **there is no axis relevant to the stated goals on which flake-pilot + Firecracker presents a genuine advantage over libkrun.** It has the same boundary class, a more demanding host-networking model, a `sudo`-on-every-call privilege model, and an image distribution model that abandons OCI without compensating benefits for the decided use case.

### 7.4 Bottom line

libkrun and the flake-pilot `firecracker-pilot` + Firecracker path share the same isolation class (KVM microVM). libkrun wins on engineering cost, host-networking simplicity, privilege model, authoring surface, image distribution, egress policy enforcement, production proof, and maintenance posture. flake-pilot's Firecracker backend is a valid microVM-based sandboxing approach with its own architectural choices — but adopting it as the runtime backend would require `dctl` to take on a substantial owned plumbing surface (KIS image distribution, manual host networking, the `firecracker-pilot` trust path) in exchange for no security gain over libkrun.

---

## 8. References

### Project-internal

- [DECISION-LINUX.md](./DECISION-LINUX.md) — narrowed implementation decision (Linux).
- [DECISION.md](./DECISION.md) — catalog-level decision, broader scope.
- [SPEC.md](./SPEC.md) — premises, threat model, tiered migration.
- [RUNTIMES.md](./RUNTIMES.md) — per-option catalog, including §4.4 (libkrun) and §5.4 (flake-pilot).

### Firecracker / KIWI / flake-pilot

- [Firecracker — homepage](https://firecracker-microvm.github.io/)
- [Firecracker — design.md (threat model, devices, jailer)](https://github.com/firecracker-microvm/firecracker/blob/main/docs/design.md)
- [Firecracker — prod-host-setup.md (no traffic filtering; jailer required)](https://github.com/firecracker-microvm/firecracker/blob/main/docs/prod-host-setup.md)
- [Firecracker — network-setup.md (TAP/NAT/bridge required)](https://github.com/firecracker-microvm/firecracker/blob/main/docs/network-setup.md)
- [Firecracker — FAQ.md](https://github.com/firecracker-microvm/firecracker/blob/main/FAQ.md)
- [Firecracker — getting-started.md](https://github.com/firecracker-microvm/firecracker/blob/main/docs/getting-started.md)
- [Firecracker — virtio-fs issue #1180 (not supported; attack-surface rationale)](https://github.com/firecracker-microvm/firecracker/issues/1180)
- [Firecracker — virtio-fs PR #1351 (rejected WIP)](https://github.com/firecracker-microvm/firecracker/pull/1351)
- [AWS bulletin 2026-015 — CVE-2026-5747 (opt-in virtio-pci OOB)](https://aws.amazon.com/security/security-bulletins/2026-015-aws/)
- [AWS bulletin 2026-003 — CVE-2026-1386 (jailer symlink LPE; host-side)](https://aws.amazon.com/security/security-bulletins/rss/2026-003-aws/)
- [OSInside/flake-pilot — repository](https://github.com/OSInside/flake-pilot)
- [OSInside/flake-pilot — networking section](https://github.com/OSInside/flake-pilot#networking-)
- [SUSE PackageHub — flake-pilot](https://packagehub.suse.com/packages/flake-pilot/)
- [KIWI NG — KIS build target](https://osinside.github.io/kiwi/building_images/build_kis.html)
- [Microarchitectural Security of AWS Firecracker VMM (arXiv 2311.15999)](https://arxiv.org/pdf/2311.15999)
- [Northflank — What is AWS Firecracker](https://northflank.com/blog/what-is-aws-firecracker)
- [Tal Hoffman — Firecracker internals deep dive](https://www.talhoffman.com/2021/07/18/firecracker-internals/)

### libkrun / Podman / `containers/` org

- [containers/libkrun](https://github.com/containers/libkrun)
- [containers/krunvm](https://github.com/containers/krunvm)
- [crun `krun.1` manpage](https://manpages.opensuse.org/Tumbleweed/crun/krun.1.en.html)
- [libkrun discussion #538 — security model](https://github.com/containers/libkrun/discussions/538)
- [Red Hat Developer — Supercharging AI isolation: microVMs with RamaLama and libkrun (Jul 2025)](https://developers.redhat.com/articles/2025/07/02/supercharging-ai-isolation-microvms-ramalama-libkrun)
- [Fedora FEDORA-2025-f8be7978e3 — libkrun (rust-openssl dependency roll)](https://linuxsecurity.com/advisories/fedora/fedora-41-libkrun-2025-f8be7978e3-security-advisory-updates-rh8lbifoalx6)
- [Fedora FEDORA-2025-c53905e83d — libkrun (crossbeam-channel dependency roll)](https://linuxsecurity.com/advisories/fedora/fedora-41-libkrun-2025-c53905e83d-ohmxvt9uvrww)

### Shared-kernel CVE precedent

- [Sysdig — runc container escape vulnerabilities (Nov 2025)](https://www.sysdig.com/blog/runc-container-escape-vulnerabilities) — CVE-2025-31133, CVE-2025-52565, CVE-2025-52881.
- [CNCF — runc container breakout vulnerabilities: a technical overview (Nov 2025)](https://www.cncf.io/blog/2025/11/28/runc-container-breakout-vulnerabilities-a-technical-overview/)
- [emirb — microvm-2026](https://emirb.github.io/blog/microvm-2026/) — hypervisor-escape bug-class economics.

### Authoring-surface context (referenced for the OCI build/distribution comparison only; not a selection criterion)

- [containers.dev — devcontainer.json specification](https://containers.dev/)
