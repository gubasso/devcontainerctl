# Sandbox Runtime — Security Specification

> Status: Draft
> Scope: Major security re-architecture of `devcontainerctl`'s container/sandbox layer.
> Audience: Maintainers, contributors, and security reviewers.
> Companion: [RUNTIMES.md](./RUNTIMES.md) — full per-option catalog and rejection reasoning.

## 0. Purpose

`devcontainerctl` (`dctl`) exists to provide a **secure, reproducible sandbox** for running AI coding agents (e.g. Claude Code, Codex CLI, Gemini CLI). These agents execute model-generated commands against arbitrary repository content, untrusted dependencies, and remote services; they must be assumed to be running attacker-controlled code at all times.

The current implementation uses Docker as the only supported runtime. This document:

1. States the project's premises — what the sandbox must achieve and what it must not be (§1).
2. Audits the current security posture (§2).
3. Defines the threat model relevant to AI-agent execution (§3).
4. Names the **viable candidate set** of runtime backends (§4). Full per-option analysis lives in `RUNTIMES.md`.
5. Proposes a tiered migration plan (§5) that preserves the project's ergonomics goals (declarative, composable, shareable configuration) while introducing a real security boundary.

**The final default backend is not chosen in this revision.** All FC-class options are kept as candidates pending a prototyping milestone (§4.4).

---

## 1. Premises

This section is load-bearing for the rest of the spec. Every later decision must be traceable to a premise here, and any deviation must be called out explicitly.

### 1.1 Functional premises (what the sandbox must achieve)

- **Hardware-virtualization boundary against adversarial code.** A serious attempt at host compromise must require a hypervisor-class bug, not a routine syscall trick or a known kernel CVE. Anything weaker than a KVM-class boundary (or platform-equivalent: Apple Virtualization.framework) is unacceptable as the *primary* isolation, regardless of how cleanly it integrates.
- **Cross-platform.** Linux is the primary target (openSUSE in particular, given the project's image base). macOS is a first-class secondary target. Windows is best-effort via WSL2.
- **OCI-image-driven authoring surface.** The existing `images/` Dockerfile flow and `devcontainer.json` schema are the user-authoring surface. The runtime swap may convert OCI images into other formats internally (rootfs tarballs, ext4, etc.); the user never authors anything other than OCI/devcontainer artifacts.
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

- **Bare Docker / Podman (rootful or rootless) as the primary boundary.** See §1.5 for reasoning. Hardened seccomp, AppArmor, and `cap-drop` are defense-in-depth, not the boundary.
- **`--privileged`, Docker socket bind-mount, `--cap-add` for non-essential caps.** Already avoided in the current configuration; explicitly disallowed going forward.
- **A runtime that requires re-implementing the OCI ecosystem from scratch** with a permanent maintenance burden the size of containerd. Targeted plumbing (rootfs builder, in-guest init, vsock channel) is acceptable; rebuilding containerd is not.
- **Hardware-attested isolation against the host (Confidential Containers / TDX / SEV-SNP)** as the threat-model framing. The host is trusted; the workload is not. We solve workload isolation, not host distrust.
- **Language-level sandboxes** (V8 isolates, WebAssembly) as the boundary. Cannot host the agent's full toolchain (`pytest`, `cargo`, `git`, native compilers).
- **CI-only / cluster-only runtimes** (firecracker-containerd, flintlock, AWS Nomad FC driver) as the laptop default. Useful as components; wrong shape for a per-developer CLI.
- **Larger-TCB hypervisors when a smaller-TCB one is available.** QEMU full-fat is rejected as the laptop default for this reason; see `RUNTIMES.md` §4.5.

### 1.5 Why bare containers are insufficient (the reasoning behind §1.4)

The shared-kernel container model is a resource-isolation boundary, not a security boundary. Three observations make it unacceptable as the primary boundary for the AI-agent threat model:

1. **Recurring container breakouts.** November 2025 alone produced **three back-to-back runc CVEs** — CVE-2025-31133, CVE-2025-52565, CVE-2025-52881 — each delivering full container breakout via mount races and procfs symlink tricks. These affect Docker, **Podman, and Kubernetes alike**. Earlier examples include Leaky Vessels (CVE-2024-21626) and CVE-2025-9074 (Docker Desktop). See [Sysdig analysis](https://www.sysdig.com/blog/runc-container-escape-vulnerabilities) and [CNCF technical overview](https://www.cncf.io/blog/2025/11/28/runc-container-breakout-vulnerabilities-a-technical-overview/).
2. **Kernel LPE cadence.** Linux kernel local-privilege-escalation surfaces at roughly monthly cadence (bpf, io_uring, netfilter, page-cache aging, and so on). Each one is a host compromise on shared-kernel runtimes. Hypervisor escapes, by contrast, are a $250K–$500K bug class ([emirb microvm-2026](https://emirb.github.io/blog/microvm-2026/)).
3. **Namespaces are a resource-control mechanism, not a security boundary.** This is a design fact, not a bug. Namespaces let the kernel partition resources for non-malicious tenants; they do not constitute a barrier against an adversary running code on the same kernel.

Rootless mode reduces *blast radius* (escape lands as the invoking user instead of host root) but does not change the *probability*: every kernel LPE still lands on the host. The November 2025 runc CVEs explicitly affect rootless Docker and Podman. Rootless containers remain valuable as a **controller around** a microVM (see `RUNTIMES.md` §4.4 for libkrun + `crun --krun`); they are not the boundary.

---

## 2. Current State (as-of audit)

`dctl` is a Bash CLI that wraps the Microsoft `devcontainer` CLI and `docker`. The user-facing schema is plain `devcontainer.json` plus a small composition system over manifest layers (`schemas/compose.schema.yaml`). All container operations shell out to `docker` and `devcontainer up/exec`.

### 2.1 Code anchors

- `bin/dctl:1-114` — entrypoint and dispatcher. No runtime selection. Docker is assumed.
- `lib/dctl/ws.sh:55-65` — every container query is `docker ps …` keyed on the `devcontainer.local_folder` label. Runtime is hardcoded to Docker at the Bash level.
- `lib/dctl/ws.sh:129-197` — `dctl ws up/reup` shells out to `devcontainer up`.
- `lib/dctl/ws.sh:252-267` — `dctl ws down` runs `docker rm -f`.
- `lib/dctl/auth.sh:60-70` — host `gh`/`glab` tokens are extracted on the host and forwarded into the container as `GH_TOKEN`/`GITLAB_TOKEN` via `--remote-env`. **This is the highest-value secret in the current threat model and is provided to the agent on every `exec`/`shell`/`run`.**

### 2.2 Configured posture

Reading `devcontainers/base/devcontainer.json:1-33` and `devcontainers/agents/devcontainer.json:106-134`:

- **Not privileged.** No `privileged: true`, no extra capabilities. Repository-wide `grep -rn "privileged|cap-add|docker.sock|userns"` returns no `--privileged`, no Docker-socket mount, no `--cap-add`. The "Docker is unsafe because of `--privileged`" critique does not apply to this project as currently shipped.
- **Runs as a non-root user.** `images/agents/Dockerfile:77-86` creates `$USERNAME` with UID/GID matched to the host at build time; `base/devcontainer.json:2` sets `remoteUser`. The container is non-root from PID 1 onward.
- **Sudo is narrowed but not eliminated.** `images/agents/Dockerfile:85` allows passwordless `sudo /usr/bin/zypper` only. Defense-in-depth, not a hard boundary: a crafted local RPM with a `%post` script still gains root inside the container (`docs/ARCHITECTURE.md:1087`).
- **Custom seccomp profile, weaker than Docker's default.** `devcontainers/agents/seccomp-bwrap.json` is **default-allow** with explicit `EPERM` denies on ~20 high-risk syscalls (`bpf`, `userfaultfd`, `perf_event_open`, `keyctl`, `kexec_*`, `init_module`, `iopl/ioperm`, `swapon`, `reboot`, `syslog`, plus legacy syscalls). The profile's `_meta` block is honest about the trade-off: it exists so `bwrap` (Codex CLI's inner sandbox) can `unshare(CLONE_NEWUSER)` without being blocked. This is materially weaker than the upstream moby default-deny baseline.
- **AppArmor and `/proc` masking are off.** `devcontainers/agents/devcontainer.json:108-110` sets `apparmor=unconfined` and `systempaths=unconfined` for the same `bwrap` reason: `bwrap` probes `/proc/sys/kernel/unprivileged_userns_clone` and bails if masked. This removes a layer that has historically blunted real-world Linux LPEs.
- **No user-namespace remap.** `updateRemoteUserUID: false` in `base/devcontainer.json:3`; the host UID is mapped 1-to-1 inside the container. There is no `userns=auto`, no rootless Docker, no `userns-remap`.
- **Bind mounts that matter:** `~/.gitconfig` (RO), `~/.config/gh`, `~/.config/glab-cli`, `~/.claude`, `~/.claude.json`, `~/.codex`, `~/.gemini`, **`/tmp` host bind**, plus `coordinator/devcontainer.json:4-10` mounting `~/Projects` read-only. The agent CLI configuration directories contain **OAuth refresh tokens** (Claude session, GitHub/GitLab tokens). Anything inside the container that can read files-as-user can exfiltrate them.
- **Network egress is open by default.** `docs/ARCHITECTURE.md:1119,1138` — bridge/NAT, outbound internet allowed (required for the model APIs). There is no egress allowlist.
- **`/tmp` is bind-mounted from the host** (`base/devcontainer.json:27-30`). Writable shared surface between host and container; not a privilege boundary, but a covert/IPC channel and a place to drop persistence.

### 2.3 Audit conclusion

The shipped profile is approximately the strongest configuration achievable while keeping a single shared kernel **and** keeping `bwrap` (the inner sandbox used by Codex CLI) functional. It is honest about its limits (`docs/ARCHITECTURE.md:1083-1142`) and avoids the worst-class mistakes commonly cited in Docker-security critiques (no `--privileged`, no socket mount, non-root inside).

For the AI-agent threat model, however, several concerns remain:

- The seccomp profile is intentionally permissive.
- AppArmor is disabled.
- The network is unrestricted.
- OAuth tokens for GitHub/GitLab/Claude are mounted into the agent's filesystem.
- The kernel boundary is shared with the host. Any kernel LPE or container-runtime escape is a host compromise.

The migration in §5 is structured to address each of these in order.

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

Requires either a runtime (runc/crun/Docker) bug or a kernel LPE.

- **November 2025** brought three back-to-back runc CVEs (CVE-2025-31133, CVE-2025-52565, CVE-2025-52881), each delivering full container breakout via mount races and procfs symlink tricks. These affect Docker, **Podman**, and Kubernetes alike.
- **Earlier examples:** Leaky Vessels (CVE-2024-21626), CVE-2025-9074 (Docker Desktop), and a continuous stream of bpf/io_uring/netfilter LPEs.

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

- Bare Docker (rootful) — `RUNTIMES.md` §1.1
- Bare Podman (rootful) — `RUNTIMES.md` §1.2
- Hardened-container path alone — `RUNTIMES.md` §1.3
- Docker rootless / Podman rootless as the boundary — `RUNTIMES.md` §2 (kept as defense-in-depth and as a controller front-end for libkrun)
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

### 5.2 Tier 1 — Runtime abstraction; keep Docker as default, add Podman-rootless

This is the cheap correctness win and the engineering precondition for Tier 2.

1. Introduce `DCTL_RUNTIME ∈ {docker, podman, kata-fc, kata-ch, krun, gvisor, apple-container}` and route every `docker` invocation in `lib/dctl/ws.sh` through a small adapter (`lib/dctl/runtime/<name>.sh`). The user-facing schema (`devcontainer.json`, manifests) does not change.
2. Add Podman rootless as the second backend, with rootless-specific Tier-0 defaults (no privileged ports, pasta networking, `userns=auto:size=65536`). Podman-rootless is treated as **defense-in-depth and a controller front-end** for §5.3, not as the security boundary.
3. Make `dctl test` runtime-aware: the same smoke-test must pass against every backend.

### 5.3 Tier 2 — FC-class hardware boundary as the recommended default (Linux + macOS)

This delivers the real hardware boundary without breaking ergonomics. Because all §4.1 candidates consume OCI images, `images/` and the Dockerfile build flow do not change at this tier.

1. Add at least one §4.1 candidate as a backend behind the same adapter introduced in Tier 1. The specific candidate (Kata-FC, Kata-CH, libkrun, or bare-FC) is chosen based on Tier 1 prototyping results and the §4.4 criteria.
2. Add **Apple `container`** as the macOS backend.
3. Add **gVisor** as the no-KVM fallback for CI and similar environments.
4. The composition layer gains a new layer kind: `runtime-policy` (e.g. `runtime: kata-ch`, `egress: allowlist`, `mounts: scoped`). Leaf-layer ergonomics remain unchanged for most users.

### 5.4 Tier 3 — Relax inner constraints once the outer boundary is a hypervisor

Once an FC-class runtime is the default, the inner-container freedom can be expanded confidently (package installs, Docker-in-Docker, build sandboxes) because the boundary is now a hypervisor rather than a syscall filter. The custom permissive seccomp profile (`devcontainers/agents/seccomp-bwrap.json`) becomes non-load-bearing and `agents-strict` can become the default profile under VM-bounded runtimes.

### 5.5 Runtime-abstraction layer (sketch)

```
lib/dctl/
  runtime/
    common.sh        # interface: rt_run, rt_exec, rt_ps, rt_rm, rt_build
    docker.sh        # current behavior, default for back-compat
    podman.sh        # rootless, pasta, userns=auto
    kata-fc.sh       # nerdctl --runtime io.containerd.kata.v2 with FC VMM config
    kata-ch.sh       # nerdctl --runtime io.containerd.kata.v2 with CH VMM config
    krun.sh          # podman --runtime krun ...
    bare-fc.sh       # dctl-owned FC controller (escape hatch)
    gvisor.sh        # nerdctl --runtime runsc ...
    apple.sh         # `container run …`
  ws.sh              # calls rt_* instead of docker
  image.sh           # calls rt_build instead of docker build
```

Runtime selection mirrors how config already composes:

1. Project leaf layer pins `runtime: kata-ch` (or any other supported value).
2. User global default in `~/.config/dctl/default/devcontainer.json` sets the user's preferred runtime.
3. `DCTL_RUNTIME` env or `--runtime` flag overrides for one-off cases.

Composable, declarative, runtime-agnostic. The same `python.yaml` manifest produces a Docker container on a CI machine without nested virt and an FC-class microVM on a KVM-equipped laptop.

---

## 6. Migration Sketch

| Step | Files touched | Effort | Risk |
|---|---|---|---|
| T0.1 — token forwarding instead of mounts | `lib/dctl/auth.sh`, `devcontainers/base/devcontainer.json:17-26`, `devcontainers/agents/devcontainer.json:112-133` | 1–2 d | Low (gh exists; Claude needs session-token forwarding equivalent) |
| T0.2 — drop host `/tmp` bind, switch to tmpfs | `devcontainers/base/devcontainer.json:27-30` | 1 h | Low |
| T0.3 — egress allowlist | new `lib/dctl/net.sh` + `nftables` shim or `slirp4netns --enable-sandbox --disable-host-loopback` | 3–5 d | Medium (UX for adding domains) |
| T0.4 — `no-new-privileges`, `cap-drop=ALL` | `devcontainers/agents/devcontainer.json:107-111` | 30 min | Low (verify Codex `bwrap` still starts) |
| T0.5 — `agents-strict` profile alongside `agents-permissive` | new `devcontainers/agents-strict/` | 1 d | Low |
| T1.1 — runtime adapter | `bin/dctl`, `lib/dctl/ws.sh`, new `lib/dctl/runtime/*.sh` | 2–3 d | Low; Docker behavior preserved |
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
- `dctl` command paths route through a runtime adapter; no direct `docker` invocation remains in `lib/dctl/`.
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
- Inner Docker-in-Docker and package installation work without weakening the host's security posture.

---

## 8. Open Questions

- **Final §4.1 backend choice.** What are the cold-start, mount-latency, devcontainer-feature-parity, and smoke-test numbers for at least two of {bare Firecracker, Kata+FC, Kata+CH, libkrun} on the developer-laptop reference hardware? Selection criteria are defined in §4.4.
- **Cross-platform mental model.** Does libkrun's macOS HVF backend reach feature parity with Apple `container`, or do we keep two backends on macOS?
- **Claude session token forwarding.** Is there a documented short-lived token export path for Claude Code, equivalent to `gh auth token`? If not, what is the minimal subset of `~/.claude` that must be projected into the container, and can it be projected as an ephemeral copy rather than a live mount?
- **Egress allowlist UX.** How should users add domains? Static manifest entries, an interactive `dctl net allow <host>` command, or both? What is the right default set?
- **CI parity.** Some CI environments lack nested virtualization. The default backend in CI must be either rootless containers + gVisor, or rootless containers with the strict profile. The spec should pick one as the documented CI default.
- **Image distribution.** Kata consumes OCI images, but rootfs construction has subtle differences (init systems, kernel modules, agent injection). Are upstream `images/agents/Dockerfile` artifacts directly compatible, or is a Kata-specific (or libkrun-specific) build target needed?
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
- [magmastonealex/firedocker](https://github.com/magmastonealex/firedocker)
- [iximiuz Labs — Firecracker hands-on](https://labs.iximiuz.com/courses/firecracker-hands-on/run-first-microvm)
- [Single-app rootfs for Firecracker (cloudkernels.net)](https://blog.cloudkernels.net/posts/fc-rootfs/)
- [buildfs (crates.io)](https://crates.io/crates/buildfs)
- [Hyperlight — Microsoft introduction (Nov 2024)](https://opensource.microsoft.com/blog/2024/11/07/introducing-hyperlight-virtual-machine-based-security-for-functions-at-scale/)
- [OSInside/flake-pilot](https://github.com/OSInside/flake-pilot)
- [SUSE Package Hub — flake-pilot](https://packagehub.suse.com/packages/flake-pilot/)

### Docker / Podman security
- [Docker — Rootless mode](https://docs.docker.com/engine/security/rootless/)
- [Docker — userns-remap](https://docs.docker.com/engine/security/userns-remap/)
- [Podman — rootless tutorial](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md)
- [Red Hat — Rootless Podman user-namespace modes](https://www.redhat.com/en/blog/rootless-podman-user-namespace-modes)
- [VS Code Dev Containers + Podman walkthrough](https://blog.okikio.dev/from-docker-to-podman-vs-code-devcontainers)

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
