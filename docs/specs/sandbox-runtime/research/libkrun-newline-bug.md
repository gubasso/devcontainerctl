# Research — libkrun newline-mangling bug in `crun --krun`

> Status: Classified — bug is in `crun --krun` / libkrun newline handling. Upstream issue not yet filed at the time of writing.
> Date: 2026-05-19
> Companions: [../decisions/03-orchestration-native.md](../decisions/03-orchestration-native.md), [../decisions/02-runtime-linux.md](../decisions/02-runtime-linux.md).

## 1. Summary

Under `podman run --runtime krun … --entrypoint /bin/sh -c '<multi-line script>'`, the **first line of the script executes correctly** and **every subsequent line is delivered to the guest shell with a stray `n` prefix on its first token** — as if a one-pass `\n` decode somewhere in the host→guest argv path emits a newline but fails to advance the input cursor past it. Default `crun` (no `--krun`) handles the same payload correctly.

Practical implication: any caller that builds a multi-line `sh -c` payload as its container entrypoint cannot start a container under `crun --krun`. `@devcontainers/cli`'s keep-alive shim is the canonical hit; this is why [../decisions/03-orchestration-native.md](../decisions/03-orchestration-native.md) commits to a native parser that never generates this shape.

The existing `dctl` runtime adapter `lib/dctl/runtime/krun.sh` is unaffected because it only ever uses argv-vector `podman exec`, never multi-line `sh -c` at container creation time.

## 2. Environment

- Host: Arch Linux, kernel `7.0.7-arch2-1`, rootless
- Podman: `5.8.2` (host install at `/usr/bin/podman`)
- `crun`: `1.27.1` (commit `3ec076b3b6714ec2f1a10533cf18d5605a6de637`, OCI spec `1.0.0`, features `+SYSTEMD +SELINUX +APPARMOR +CAP +SECCOMP +EBPF +CRIU +LIBKRUN +YAJL`)
- Arch packages: `crun 1.27.1-1`, `libkrun 1.18.0-1`, `libkrunfw 5.3.0-1`, `krun 1.27.1-1`

## 3. Minimal repro

Four host commands isolate the bug from any caller. Capture verbatim stdout/stderr and exit codes for each before drawing conclusions.

### 3.1 Two-line script under `--runtime krun`

```bash
podman run --rm --runtime krun --entrypoint /bin/sh \
  mcr.microsoft.com/devcontainers/base:debian \
  -c $'echo line1\necho line2'
```

Observed (2026-05-19, after `podman rm -f` of any leftover container):

```
line1
/bin/sh: 2: necho: not found
exit=127
```

`line1` runs correctly; `echo line2` is delivered as `necho line2` — the `\n` produced a newline *and* the leading `e` of the next line was consumed as if it were the `n` of the escape.

### 3.2 Same script under default `crun` (control)

```bash
podman run --rm --entrypoint /bin/sh \
  mcr.microsoft.com/devcontainers/base:debian \
  -c $'echo line1\necho line2'
```

Observed:

```
line1
line2
exit=0
```

Clean. The bug is present only on the `--runtime krun` path.

### 3.3 CLI-shaped shim under `--runtime krun`

```bash
podman run --rm --runtime krun --entrypoint /bin/sh \
  mcr.microsoft.com/devcontainers/base:debian \
  -c $'echo Container started\ntrap "exit 0" 15\n\necho after-trap\nexec sleep 2' -
```

Observed:

```
Container started
-: 2: ntrap: not found
-: 3: n: not found
-: 4: necho: not found
-: 5: nexec: not found
exit=127
```

The shape mirrors what `@devcontainers/cli` installs as its keep-alive shim. Same failure pattern as §3.1 — line 1 runs, every subsequent line is `n`-prefixed.

### 3.4 Same shim under default `crun` (control)

```bash
podman run --rm --entrypoint /bin/sh \
  mcr.microsoft.com/devcontainers/base:debian \
  -c $'echo Container started\ntrap "exit 0" 15\n\necho after-trap\nexec sleep 2' -
```

Observed:

```
Container started
after-trap
exit=0
```

Clean. Confirms the failure is runtime-specific.

## 4. Classification

The four results above map cleanly to: **bug is in `crun --krun` / libkrun newline handling, not in any caller's argv construction.** A two-line `echo` script is sufficient; the CLI's shim shape is a more elaborate trigger of the same bug, not a different bug.

Mechanism inferred from the stderr shape: a literal `\n` in the host-side `-c` payload is being delivered to the guest shell with the newline emitted but the input cursor failing to advance past it, so each subsequent line is read as `n` + original-first-character + rest. In §3.3, line 1 (`echo Container started`) runs correctly; then `trap` → `ntrap`, the blank line → `n`, `echo after-trap` → `necho after-trap`, `exec sleep 2` → `nexec sleep 2`. Consistent with a one-pass `\n` decode somewhere in the host→guest argv path through libkrun (vsock + init/agent).

The existing `dctl` direct adapter (`lib/dctl/runtime/krun.sh`) is unaffected because it only sends argv vectors to `podman exec` — no embedded multi-line shell script — so it never reaches the broken decode path.

## 5. Prior art (web search, 2026-05-19)

No public report of `@devcontainers/cli` + `podman --runtime krun` working end-to-end at the time of investigation. Closest upstream issues, all open at the time:

- [containers/crun#1098](https://github.com/containers/crun/issues/1098) — `podman exec` into a krun'd container does not enter the VM (3+ years open).
- [containers/libkrun#104](https://github.com/containers/libkrun/issues/104) — `podman run` with krun drops env from image config.
- [containers/libkrun#273](https://github.com/containers/libkrun/issues/273) — krun argument-passing bug (`--` not forwarded correctly).
- [containers/podman#28067](https://github.com/containers/podman/issues/28067) — TUI character handling broken under krun (Enter/newlines not handled correctly).
- [containers/podman#21083](https://github.com/containers/podman/issues/21083) — `--init` not supported under libkrun.
- [containers/podman#24618](https://github.com/containers/podman/issues/24618) — race condition with krun on Fedora 40.

Red Hat's public libkrun investment (2024–2026) targets AI/GPU isolation; no maintainer statement on exec / lifecycle-hook semantics for the krun handler.

## 6. Upstream filing

When filed, link the issue here and update the status banner at the top of this document.

Suggested filing target: **containers/crun + containers/libkrun**, with §3 as the minimal repro. Reference [containers/libkrun#273](https://github.com/containers/libkrun/issues/273) (argument passing) and [containers/podman#28067](https://github.com/containers/podman/issues/28067) (TUI newlines) as likely related symptoms of the same root cause.

<!-- TODO(upstream-url): replace with the filed issue URL once reported. Search: TODO(upstream-url) -->

## 7. Implications for `dctl`

The orchestration consequences are captured in [../decisions/03-orchestration-native.md](../decisions/03-orchestration-native.md). Summary:

- The bug rules out any orchestration path that installs a multi-line `sh -c` blob as the container entrypoint under `--runtime krun`.
- The bug does **not** affect argv-vector `podman exec` after the container is up. The existing `lib/dctl/runtime/krun.sh` adapter is bug-immune by construction and is the production path.
- The bug-immune-shape invariant is locked in by a `dctl doctor` probe and code-review discipline; see [../decisions/03-orchestration-native.md §4.1](../decisions/03-orchestration-native.md).

## 8. Things to re-check if upstream fixes the bug

- Whether the `${localEnv:*}` substitution helper in `dctl` should be replaced by `devcontainer read-configuration` for spec parity. Probably no — the native helper is small, covers the configurations actually shipped, and avoids re-introducing CLI concepts that do not match `dctl`'s posture.
- Whether the features ecosystem becomes worth adopting once `@devcontainers/cli` works again. Decide based on whether a real configuration needs a feature, not on availability.
