# Phase 00 — Preflight & host environment (prex task brief)

> Status: Pending
> Companion docs (Codex must read these in stage 1):
> - [docs/specs/sandbox-runtime/SPEC.md](../SPEC.md)
> - [docs/specs/sandbox-runtime/DECISION.md](../DECISION.md)
> - [docs/specs/sandbox-runtime/DECISION-LINUX.md](../DECISION-LINUX.md)
> - [docs/specs/sandbox-runtime/RUNTIMES.md](../RUNTIMES.md)
> - [docs/specs/sandbox-runtime/IMPLEMENTATION-PLAN.md](../IMPLEMENTATION-PLAN.md) (master overview)
> Reference implementation: [`val4oss/ai-agents-sandbox`](https://github.com/val4oss/ai-agents-sandbox) — port `_check_microvm` (`ai-agents-sandbox.sh:102-156`) and the `MIN_LIBKRUN_VER` gate (`ai-agents-sandbox.sh:45`).
> Depends on: nothing — this is the foundational round.
> Output of this round: `dctl doctor` works, `docs/INSTALL.md` exists, host operators can verify their box supports libkrun + rootless Podman.

## Task

Establish host requirements and a reproducible bootstrap path for the libkrun + rootless Podman stack on openSUSE Tumbleweed (primary). Add a new top-level `dctl doctor` subcommand that probes the host and emits precise remediation messages on each failure. Document the install path in a new `docs/INSTALL.md`. Update `docs/QUICKSTART.md` and `docs/CLAUDE.md` so new users are not directed at the old Docker + `devcontainer` CLI stack. Add a deprecation banner to `dctl test` (Phase 2 will rewire it; until then, point users at `dctl doctor`).

## Preconditions (must already be true on `develop`)

- `make check` is currently green on `develop`.
- `bin/dctl` dispatcher at `bin/dctl:75-109` is the flat case-statement currently shipping (adding a new arm is mechanical).
- `lib/dctl/common.sh:31-47` defines `log`/`warn`/`err`/`require_cmd` — reuse them.
- `lib/dctl/test.sh:30-67` defines `check_pass`/`check_fail`/`_print_summary` — reuse the shape.

## Scope (in this round)

- **New file:** `docs/INSTALL.md` (host packages, KVM group, OBS repo enablement, smoke-test commands).
- **New file:** `lib/dctl/doctor.sh` (the doctor module — a new top-level command, not an extension of `dctl test`).
- **New file:** `lib/dctl/runtime/common.sh` (Phase 0 lands an empty/skeletal version holding `MIN_LIBKRUN_VER=1.18.0` and the future `rt_*` interface contract comments; Phase 1 fills in the dispatcher).
- **Edit:** `bin/dctl` — add a `doctor)` arm in the dispatcher at `bin/dctl:75-109`.
- **Edit:** `lib/dctl/test.sh` — add a one-line deprecation banner at the top of `cmd_test` (or equivalent entry point) pointing to `dctl doctor`. No behavioral change.
- **Edit:** `docs/QUICKSTART.md:5-7` — Prerequisites block: swap *"Docker with buildx"* → *"Podman (rootless) + libkrun + crun-krun (run `dctl doctor` to verify)"*; drop the *"Dev Container CLI installed (`devcontainer`)"* line.
- **Edit:** `docs/CLAUDE.md` — Quick Orientation block: swap *"Pre-built Docker images"* and *"managed Dockerfiles"* for Podman / Containerfile equivalents.

## Out of scope for this round (DO NOT touch)

- The `lib/dctl/runtime/krun.sh` implementation — Phase 1's job.
- Any `dctl test` rewire beyond the deprecation banner — Phase 2's job. `lib/dctl/test.sh:216,230,253,263` still shell out to `docker` + `devcontainer` and that is intentional in the interim.
- The full repo-wide Dockerfile→Containerfile rename + docs sweep — Phase 7's job. Only `docs/QUICKSTART.md` and `docs/CLAUDE.md` are touched here because their entry-point taglines would otherwise route new users to a broken install.
- Phase 1.5 doctor-module split (`lib/dctl/commands/doctor/*.sh`) — Phase 1.5's job. This round ships the flat `lib/dctl/doctor.sh`.

## Implementation guidance

### `docs/INSTALL.md` — host packages

openSUSE Tumbleweed primary. Required packages: `podman`, `crun` (built with libkrun handler), `libkrun`, `libkrunfw`. **Do not** hardcode SONAME-versioned package names (`libkrun1`, `libkrunfw5`) — `zypper` resolves the soname. The decisive check is `crun --version | grep -q '+LIBKRUN'`, not a numeric floor.

Network backend: `slirp4netns` **or** `passt`/`pasta`. Podman 5.8 (Mar 2026) defaults rootless networking to **pasta**, not slirp4netns. `dctl` will pin one explicitly in Phase 2's `rt_run` invocation; record the choice in `DECISION-LINUX.md` before Phase 2 starts.

Version reality (as of 2026-05): upstream `crun` is 1.27.1; upstream `libkrun` is 1.18.0. Tumbleweed snapshots track crun closely (1.26–1.27.x), but the **official Tumbleweed repos lag libkrun** (currently ≤ 1.15.1 per `software.opensuse.org/package/libkrun`; 5.2.x available on OBS `Virtualization/libkrunfw`). **Document the OBS `Virtualization` repo enable step explicitly** — calling this "Tumbleweed primary" with `libkrun ≥ 1.18` is currently false without that step.

`kvm` group membership for `$USER`: `sudo usermod -aG kvm $USER && newgrp kvm` (group membership is not retroactive in the current shell). Tumbleweed uses `kvm` as the `/dev/kvm` group — not `qemu` or `libvirt`.

`/etc/subuid` and `/etc/subgid` entries for `$USER` (rootless Podman cannot create user-namespaces without these).

For openSUSE Leap 16: add the `Virtualization:containers` + `Virtualization` zypper repos (mirrors ai-agents-sandbox README "openSUSE Leap 16.0").

### `lib/dctl/doctor.sh` — probe set (roughly in print order)

1. **`crun --version | grep -q '+LIBKRUN'`** — canonical build-flag check. The handler's `.feature_string = "LIBKRUN"` is declared in [containers/crun `src/libcrun/handlers/krun.c:978`](https://github.com/containers/crun/blob/main/src/libcrun/handlers/krun.c) and printed by `print_version()` via `libcrun_handler_manager_print_feature_tags()` in `src/libcrun/custom-handler.c`. The token is **`+LIBKRUN`**, **not** `+CRUN_KRUN` (an earlier draft was wrong). Do **not** fall back to `crun --help | grep -- --krun` — that flag does not exist; the handler is selected via the `/usr/bin/krun` symlink or `--annotation run.oci.handler=krun`.
2. **`command -v krun`** + `readlink -f $(command -v krun)` — confirms the `crun → krun` symlink shipped by the `crun-krun` integration is present.
3. **End-to-end smoke:** `podman run --runtime krun --rm <tiny-image> /bin/true` followed by `podman inspect <ctr> --format '{{.OCIRuntime}}' == krun`. This is the only **decisive** check — `/dev/kvm` rw + kvm group + `+LIBKRUN` are necessary but not sufficient (cf. [containers/crun#1894](https://github.com/containers/crun/issues/1894): `krun` can fail despite `/dev/kvm` rw without a posix ACL). Skip-gracefully if `podman` is missing (the earlier probes already failed).
4. **`libkrun.so` version ≥ `MIN_LIBKRUN_VER`** — resolve the actual shared object via `ldconfig -p | awk '/libkrun\.so/{print $4}'` (do **not** hardcode the SONAME-versioned filename); extract the version from the resolved path or via `readelf -d`. The constant lives in `lib/dctl/runtime/common.sh` (this round creates it as `MIN_LIBKRUN_VER=1.18.0`) — Phase 1 reuses it.
5. **`/dev/kvm`** exists and is rw for `$USER`; warn-only check the posix ACL with `getfacl /dev/kvm` to flag crun#1894 early.
6. **`kvm` group membership** for `$USER` — fail if absent.
7. **`/etc/subuid` and `/etc/subgid`** each contain a range allocated to `$USER`.
8. **`podman info --format '{{.Host.CgroupVersion}}' == v2`** — rootless requires cgroups v2.
9. **`podman info --format '{{.Host.CgroupManager}}' == systemd`** — normal rootless shape on Tumbleweed.
10. **`podman info --format '{{.Host.OCIRuntime.Name}}'`** — surfaces a default-`runc` install that needs explicit `--runtime krun`.
11. **`podman info --format '{{.Host.NetworkBackend}}'`** — surfaces pasta vs slirp4netns so the operator can compare against `dctl`'s pinned choice.
12. **`podman unshare cat /proc/self/uid_map`** returns ≥ 2 lines — end-to-end userns smoke.
13. **`sysctl kernel.unprivileged_userns_clone == 1`** — warn-only on Tumbleweed (default is `1`); load-bearing on hardened kernels.
14. **Nested-virt heuristic** — `grep -E 'vmx|svm' /proc/cpuinfo` is **warn-only**, not a gate; surfaces "you're inside a VM; libkrun may run but performance will be degraded."
15. **Emit precise remediation messages** on each failure (port the message catalog from `ai-agents-sandbox.sh:102-156`).

Each probe maps to a `check_pass`/`check_fail` line in the same shape as `lib/dctl/test.sh:30-67`. Reuse `log`/`warn`/`err`/`require_cmd` from `lib/dctl/common.sh:31-47`. Source `lib/dctl/common.sh` from the new module; do not duplicate helpers.

### `bin/dctl` dispatch

Add a `doctor)` arm in the case statement at `bin/dctl:75-109`. Source `lib/dctl/doctor.sh` from the module-source block at `bin/dctl:14-20` (this is the pre-Phase-1.5 flat layout; Phase 1.5 will rewrite to autoload).

### `lib/dctl/test.sh` deprecation banner

Add a single-line warning at the top of the entry function: `warn "'dctl test' will be rewired to podman in Phase 2; use 'dctl doctor' to verify host setup."` Do not change any other behavior. This satisfies scope-decision #2 (no silent breakage) without doing Phase 2's work.

## Acceptance gates (all must pass before stage 4 review approves)

- `make check` passes.
- `dctl doctor` runs on the developer's openSUSE Tumbleweed host and prints all 14+ probes. Failing probes show actionable remediation text.
- `dctl doctor` exits 0 when every probe passes; exits non-zero with a precise summary when any fail.
- `bin/dctl --help` lists the new `doctor` subcommand.
- `dctl test --help` (or its first line of output) shows the Phase-2 rewire banner.
- `docs/QUICKSTART.md` no longer mentions Docker or the `devcontainer` CLI in its Prerequisites block.
- `docs/CLAUDE.md` Quick Orientation block reads as Podman/Containerfile, not Docker/Dockerfile.
- `lib/dctl/runtime/common.sh` exists and exports `MIN_LIBKRUN_VER=1.18.0` (and a sourced-once guard).
- `grep -rn '+CRUN_KRUN' lib/ docs/` returns empty (the wrong token must not appear anywhere).

## Risks & known gotchas

- **Tumbleweed package lag.** The "Tumbleweed primary" framing is only true if the user enables the OBS `Virtualization` repo. INSTALL.md must lead with that step or new users will install libkrun ≤ 1.15.1 and silently miss Phase 1's `MIN_LIBKRUN_VER` floor.
- **Group membership not retroactive.** Adding `$USER` to `kvm` requires `newgrp kvm` or a re-login. The doctor must give the user clear remediation text on group-membership failure.
- **libkrun #674 is still open as of 2026-05** (vsock TX BufDescTooSmall on guest kernels ≥ 6.2). The Phase 1 workaround lands in `lib/dctl/runtime/krun.sh`. For Phase 0, surface it in `docs/INSTALL.md` as a known limitation but do not gate doctor on it.
- **crun #1894** (`/dev/kvm` posix-ACL trap) — the `getfacl /dev/kvm` warn-only check exists to catch this. Do not promote it to a hard gate without local reproduction.
- **`docs/CLAUDE.md` edit is small and surgical** — Phase 7 does the full sweep. Touch only the Quick Orientation block; leave the rest alone.

## Plan-file cleanup (Codex must perform in stage 3, as part of the implementation commit)

1. Delete this file: `docs/specs/sandbox-runtime/plans/00-preflight-doctor.md`.
2. Update `docs/specs/sandbox-runtime/plans/README.md`: this round's row `Status` → `Done — <commit-sha> — <date>`.
3. Promote durable content:
   - `docs/INSTALL.md` is the permanent home. Nothing else from this brief needs promotion — the probe rationale stays in the source comments of `lib/dctl/doctor.sh`.
   - The references block (the URLs cited in §"Implementation guidance" above) moves into `docs/INSTALL.md` as a "References" footer section.
4. Update `docs/specs/sandbox-runtime/IMPLEMENTATION-PLAN.md`: tick the Phase 0 row in the `## Per-round briefs` section.

## References (move into `docs/INSTALL.md` on cleanup)

**crun + libkrun upstream:**
- crun handler source (`.feature_string = "LIBKRUN"`): <https://github.com/containers/crun/blob/main/src/libcrun/handlers/krun.c>
- crun feature-tag printer (`libcrun_handler_manager_print_feature_tags`): <https://github.com/containers/crun/blob/main/src/libcrun/custom-handler.c>
- crun krun.1 manpage on Tumbleweed: <https://manpages.opensuse.org/Tumbleweed/crun/krun.1.en.html>
- crun releases (latest 1.27.1): <https://github.com/containers/crun/releases>
- libkrun releases (latest 1.18.0, 2026-04-24): <https://github.com/containers/libkrun/releases>
- libkrun README (TSI networking limits): <https://github.com/containers/libkrun>

**Known issues to surface in the doctor:**
- libkrun #674 — vsock TX BufDescTooSmall on guest kernels ≥ 6.2 (open as of 2026-05): <https://github.com/containers/libkrun/issues/674>
- crun #1894 — `krun` fails despite `/dev/kvm` rw without posix ACL: <https://github.com/containers/crun/issues/1894>

**openSUSE packaging:**
- Tumbleweed package pages: <https://software.opensuse.org/package/crun>, <https://software.opensuse.org/package/libkrun>, <https://software.opensuse.org/package/libkrunfw>
- OBS `Virtualization/libkrunfw` (latest 5.2.x): <https://build.opensuse.org/package/show/Virtualization/libkrunfw>
- openSUSE Factory ML — original libkrun submission: <https://lists.opensuse.org/archives/list/factory@lists.opensuse.org/thread/MO4PYYD3BEUJCUWGJQCQ2P7OW4LTG336/>
- SUSE Package Hub — libkrun (Leap 15 SP7): <https://packagehub.suse.com/packages/libkrun/>
- Fedora — `crun-krun` subpackage: <https://packages.fedoraproject.org/pkgs/crun/crun-krun/>

**Rootless Podman preflight:**
- SUSE — rootless Podman guide: <https://documentation.suse.com/smart/container/html/rootless-podman/index.html>
- Podman — rootless tutorial: <https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md>
- Red Hat — rootless Podman cgroups v2 solution: <https://access.redhat.com/solutions/5913671>
- Arch wiki — Podman (`unprivileged_userns_clone`): <https://wiki.archlinux.org/title/Podman>
- podman-info(1): <https://docs.podman.io/en/latest/markdown/podman-info.1.html>
- podman-network(1): <https://docs.podman.io/en/latest/markdown/podman-network.1.html>

**Networking shift (Podman 5.8, Mar 2026):**
- pasta-default rootless networking: <https://sanj.dev/post/podman-pasta-vs-slirp4netns-networking>

**KVM / `/dev/kvm` group:**
- openSUSE wiki — KVM: <https://en.opensuse.org/KVM>
- Arch BBS — classic `/dev/kvm` group-id discussion: <https://bbs.archlinux.org/viewtopic.php?id=69454>
