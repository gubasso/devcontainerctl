# Sandbox Runtime — Orchestration Layer Decision

> Status: Decided
> Decision date: 2026-05-19
> Scope: Orchestration layer of `dctl` on Linux — how `devcontainer.json` is parsed, how lifecycle hooks run, how layers compose, how variables expand. Independent of the runtime adapter, which remains as decided in [02-runtime-linux.md](02-runtime-linux.md).
> Companions: [02-runtime-linux.md](02-runtime-linux.md), [../spec.md](../spec.md), [../research/libkrun-newline-bug.md](../research/libkrun-newline-bug.md).
> Supersedes: an earlier "re-adopt `@devcontainers/cli` behind the krun boundary" plan, blocked at its Phase 0 spike on 2026-05-19. That plan is not retained; this document captures the resulting commitment.

## 0. Summary

`dctl` parses `devcontainer.json` **natively**. The upstream Microsoft `@devcontainers/cli` is **not** a dependency of any `dctl` code path — neither for `up`, `exec`, `build`, lifecycle, features, nor variable substitution. The composition system (`schemas/compose.schema.yaml` + YAML manifests) and the runtime adapter (`lib/dctl/runtime/krun.sh`) together implement everything `dctl` needs from the devcontainer spec for the configurations this project actually ships.

| Slot | Pick | One-line rationale |
|---|---|---|
| `devcontainer.json` parser | **`dctl` native (jq-based)** | Already implemented across `lib/dctl/`; covers every key the shipped configs use. |
| Composition | **YAML manifests under `devcontainers/` + `schemas/compose.schema.yaml`** | Already implemented; merges layers in declared order; leaf layer protected. |
| Variable substitution (`${localEnv:*}`, `${localWorkspaceFolderBasename}`, `${containerEnv:*}` in `remoteEnv`) | **`dctl` native, one pass at config-resolution time** | Small, well-bounded helper. The only gap to existing configurations. |
| Lifecycle hooks | **`lib/dctl/lifecycle.sh`** | Covers the spec keys actually used (`postCreateCommand`, `postStartCommand`); the four unused keys are added only if a real configuration needs them. |
| Devcontainer features (OCI artifact installs) | **Not implemented; not needed** | Shipped configurations use baked images (`devcontainers/agents/`, `devcontainers/base/`, etc.) instead of feature pulls. Revisit only when a concrete configuration requires a feature. |
| Bug-immune invariant | **No code path may stuff a multi-line `sh -c` blob through `podman run … --runtime krun`** | Enforced by `lib/dctl/runtime/krun.sh`'s argv-vector design. Locked in with a doctor probe (§4.1). |

---

## 1. Decision criteria

In priority order:

1. **Security boundary unchanged.** Any orchestration choice must preserve the [02-runtime-linux.md](02-runtime-linux.md) invariants — libkrun via `crun --krun`, rootless Podman, KVM-class boundary, no shared-kernel fallback on developer workstations.
2. **No regressions vs. the existing shipped configurations.** The user's working `~/.dotfiles/dctl/` set (11 layers, 8 composition manifests, 3 custom Containerfiles, `postCreateCommand` + `postStartCommand` only, 8 host-env substitution patterns, zero `features:` blocks) must keep working without rewrites.
3. **Minimize code `dctl` has to own** consistent with criteria 1 and 2. Borrow from upstream where it is free; do not adopt upstream code that costs more than it saves.
4. **Bug-immune by construction.** The libkrun newline-mangling bug (see [../research/libkrun-newline-bug.md](../research/libkrun-newline-bug.md)) makes any path that delivers multi-line shell payloads through `podman run --runtime krun … -c '<script>'` structurally unusable. The orchestration layer must avoid that shape everywhere.

Explicitly **not** criteria:

- **Devcontainer spec parity for its own sake.** Spec features `dctl` configurations do not use (the `features` ecosystem, `customizations.vscode`, `forwardPorts`, the four unused lifecycle keys) are out of scope. They can be added when a concrete need arises, not preemptively.
- **VS Code Remote-Containers / GitHub Codespaces compatibility.** Already excluded as a goal by [02-runtime-linux.md §1](02-runtime-linux.md).

---

## 2. Decision: `dctl` parses `devcontainer.json` natively

### 2.1 What this rules out

The orchestration question that motivated the earlier blocked plan was: *should `dctl` delegate to `@devcontainers/cli` for parsing, substitution, lifecycle, features, and build, keeping its own code only for the krun adapter?* The answer here is **no**, for three converging reasons:

1. **The CLI is structurally incompatible with `crun --krun`.** Its keep-alive shim is a multi-line `sh -c` blob installed as the container entrypoint. That is the exact shape the libkrun newline bug ([../research/libkrun-newline-bug.md](../research/libkrun-newline-bug.md)) mangles. Every `devcontainer up` against `--runtime krun` fails in the same way, regardless of image or `remoteUser`. The CLI cannot be made to work with this runtime without either an upstream libkrun fix (no near-term timeline) or a runtime swap (out of scope; would require revising [02-runtime-linux.md](02-runtime-linux.md)).
2. **The CLI brings concepts that do not match this stack.** Its built-in assumption of a `vscode` user is not compatible with this project's image-agnostic posture ([../spec.md](../spec.md) §1.3 ergonomics; this project picks base images for sandbox-runtime properties, not for editor convention). Its "workspace-folder" model is not the same as `dctl ws`'s workspace-label-matched container identity. Reconciling them is busywork that buys nothing the shipped configurations need.
3. **The features ecosystem — the main argument for adopting the CLI — is unused.** The shipped layers (`devcontainers/agents/`, `devcontainers/base/`, etc.) bake their toolchains directly into custom Containerfiles. Migrating to the features ecosystem would be a parallel-track project; it is not required to get the existing configurations working.

### 2.2 What `dctl` owns vs. what stays upstream

| Owned by `dctl` (native) | Owned upstream |
|---|---|
| `devcontainer.json` parse and merge (`lib/dctl/_lib/json/merge_configs.sh`, `validate_layer.sh`). | Podman, crun, libkrun, the OCI runtime spec. |
| YAML layer composition (`schemas/compose.schema.yaml`, `lib/dctl/_lib/yaml/`). | `jq`, `yq` as read-only helpers. |
| Variable substitution pass (to be added — §2.3). | None. |
| Lifecycle dispatch (`lib/dctl/lifecycle.sh`, currently `postCreateCommand` + `postStartCommand`). | None. |
| Runtime adapter (`lib/dctl/runtime/krun.sh`). | `podman exec` / `podman run` semantics. |
| The bug-immune-shape invariant (§4.1). | The libkrun bug itself (upstream concern; do not block on it). |

The runtime adapter `lib/dctl/runtime/krun.sh` is already bug-immune by construction: every command into the microVM goes through `podman exec` as an argv vector, never as a multi-line `sh -c` payload. Container startup uses the image's own entrypoint, not an injected shell shim. This is the load-bearing property and is preserved by every change in this document.

### 2.3 The actual gap: variable substitution

Existing `dctl` config-resolution does not expand the spec's `${...}` substitution tokens at runtime. A regex-replace helper exists for validation (`lib/dctl/commands/test/run.sh:_resolve_local_env`); it is not yet applied to the resolved config before `podman` invocation.

The shipped configurations use eight host-env patterns plus a workspace basename:

| Pattern | Source | Example use |
|---|---|---|
| `${localEnv:USER}` | host `$USER` | `remoteUser`, volume names |
| `${localEnv:HOME}` | host `$HOME` | mount sources/targets |
| `${localEnv:TERM}` | host `$TERM` | terminal env passthrough |
| `${localEnv:KITTY_LISTEN_ON}`, `${localEnv:KITTY_WINDOW_ID}` | host kitty env | terminal-integration env |
| `${localEnv:DOTFILES}` | host dotfiles repo path | shell/agent/nvim config mounts |
| `${containerEnv:PATH}` | container's own `PATH` | `remoteEnv` `PATH` composition |
| `${localWorkspaceFolderBasename}` | basename of workspace folder | container `name` field |

Implementation shape: one helper in `lib/dctl/runtime/common.sh` (or a sibling) that walks the resolved JSON, applies the substitutions, and returns the expanded config to the adapter. Apply it after layer merge, before any `podman` invocation. Estimated effort: a few hours, including tests.

### 2.4 Lifecycle parity

`lib/dctl/lifecycle.sh` currently dispatches `postCreateCommand` and `postStartCommand`. The other spec keys (`initializeCommand`, `onCreateCommand`, `updateContentCommand`, `postAttachCommand`) are not implemented. None of the shipped configurations or the user's `~/.dotfiles/dctl/` set use them. Add them only when a real configuration requires one; the dispatcher structure is already in place for trivial extension.

### 2.5 Devcontainer features ecosystem

Not implemented; not required by any current configuration. The shipped layers replace what `features:` would do with hand-curated Containerfile layers (`devcontainers/agents/`, `devcontainers/base/`, etc.). When a future configuration genuinely needs a feature from `ghcr.io/devcontainers/features/`, evaluate then whether to ship a scoped resolver or to bake an equivalent layer. Do not build the resolver speculatively.

---

## 3. Why not delegate to `@devcontainers/cli`

The earlier plan proposed adopting `@devcontainers/cli` as the orchestrator behind the krun boundary, enforcing krun selection through two independent layers (`runArgs` in manifests + a scoped `CONTAINERS_CONF`). Phase 0 of that plan was executed on 2026-05-19 and produced the findings in [../research/libkrun-newline-bug.md](../research/libkrun-newline-bug.md). The minimal repro (two-line `echo` under `--runtime krun`) confirmed the bug is in `crun --krun` / libkrun, not in the CLI's argv construction. Strategy `CONTAINERS_CONF` did not help because runtime selection was not the failing layer — runtime startup was.

The CLI's keep-alive shim must traverse the libkrun argv codec at container creation time, before any `exec` channel exists. There is no CLI configuration that disables the shim; the shim is how the CLI maintains the long-lived shell server it uses for every subsequent operation. So as long as the runtime is `crun --krun` and the libkrun newline path is unfixed upstream, `@devcontainers/cli` cannot bring a container up.

Narrow integrations (CLI for `read-configuration` only, keep the direct adapter for run/exec) were considered. They are cleaner than full adoption but still leak CLI concepts into the stack (workspace-folder model, vscode-user defaults) without buying capability the shipped configurations need. They are catalog-only here; if a real configuration ever needs the spec's variable substitution to handle a case `dctl`'s own substitution helper does not cover, revisit then.

---

## 4. Invariants and enforcement

### 4.1 Bug-immune-shape invariant

**`dctl` MUST NOT generate any `podman run … --runtime krun … --entrypoint /bin/sh -c '<multi-line script>'` invocation.** This is the shape that trips the libkrun newline bug. The current `lib/dctl/runtime/krun.sh` does not generate this shape and must not start.

Enforcement:

- **Code review** for any change to `lib/dctl/runtime/krun.sh` or any helper that constructs `podman run` argv. New `--entrypoint` overrides require explicit justification that the payload is single-line.
- **`dctl doctor` probe** that scans the resolved `podman run` argv for the disallowed shape on a known-good fixture and fails loud on regression. Implementation tracked as part of the doctor surface in `lib/dctl/commands/doctor/`.
- **Pre-commit lint** (optional): a `rg` rule rejecting commits that introduce literal `--entrypoint.*sh.*-c` near `--runtime krun` in `lib/dctl/`.

### 4.2 Composition unchanged

The YAML manifest model in `schemas/compose.schema.yaml` is the user-facing composition surface. Adding native parse + substitution does not change the schema or the merge semantics; it only ensures the merged config is fully resolved before invocation.

### 4.3 Native substitution stays in `dctl`

If a future configuration uses substitution patterns the helper does not cover, extend the helper. Do not adopt an out-of-process substituter (including `devcontainer read-configuration`) as a workaround — the in-process pass is the canonical implementation.

---

## 5. Out of scope

| Item | Status |
|---|---|
| Reviving the `@devcontainers/cli` adoption plan | Closed. Reopen only if libkrun's newline path is fixed upstream **and** a concrete need for features/substitution beyond the native helper appears. |
| Implementing a devcontainer features resolver | Catalog-only. Implement when a configuration genuinely requires it. |
| Implementing `initializeCommand`, `onCreateCommand`, `updateContentCommand`, `postAttachCommand` | Add on demand. The dispatcher structure in `lib/dctl/lifecycle.sh` supports extension. |
| VS Code Remote-Containers / Codespaces compatibility | Out of scope per [02-runtime-linux.md §1](02-runtime-linux.md). |

---

## 6. Risks accepted

1. **Native substitution drift from spec.** `dctl`'s substitution helper covers the patterns the shipped configurations use; corner cases the spec defines (e.g. nested `${...}`, `${containerWorkspaceFolder}`) are not implemented until a configuration needs them. A future configuration may surface an unhandled pattern. Mitigation: helper is small and extension is cheap.
2. **No features ecosystem.** If the community ships a feature this project would benefit from (e.g. a complex toolchain installer), `dctl` consumes it by porting it to a Containerfile layer or by writing a scoped fetcher then. Mitigation: documented, finite cost when it arises.
3. **Upstream `@devcontainers/cli` work does not benefit `dctl` automatically.** This is intentional. The trade-off is no longer paying the CLI's incompatibility costs.
4. **The bug-immune-shape invariant is enforced socially + by doctor probe, not by the type system.** A future PR could in principle introduce a multi-line `-c` entrypoint by mistake. Mitigation: the doctor probe + code-review guidance keep the surface narrow; the existing adapter is the design template.

---

## 7. Concrete next steps

1. Implement the native substitution pass in `lib/dctl/runtime/common.sh` (or a sibling), exercised against the patterns enumerated in §2.3.
2. Add the bug-immune-shape doctor probe in `lib/dctl/commands/doctor/`.
3. Run the existing test suite against representative shipped manifests to confirm no regression.

These three steps close the gap between today's `dctl` and "every shipped configuration works natively, end to end, with the runtime contract from [02-runtime-linux.md](02-runtime-linux.md) preserved."
