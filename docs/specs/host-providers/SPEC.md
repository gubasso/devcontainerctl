# Host Providers — Manifest-Declared Lifecycle Executables

> Status: Implemented
> Scope: How a compose manifest hands parts of the workspace lifecycle to host executables dctl knows nothing about — and what those executables owe dctl back.
> Audience: Maintainers, contributors, and authors of host tooling (nix-secrets apps, dotfile repos) that wants dctl to run its setup around containers.
> Companion: [../secret-forwarding/SPEC.md](../secret-forwarding/SPEC.md) — the forge-seed contract this generalizes.

## 0. Purpose

Some container setups need host-side work dctl cannot and should not own: mounting an overlay filesystem, snapshotting a database, seeding a directory, refreshing credentials. dctl already runs one such contract (forge-seed) as a hardcoded special case in `lib/dctl/auth.sh`. This document specifies the general mechanism: a compose manifest declares **providers** — host executables invoked around the workspace lifecycle — and dctl composes their answers into the `devcontainer` CLI invocation. dctl stays agnostic about what a provider manages; the provider implementation lives with the host configuration that owns it (nix-secrets' `dctl-nix-store` is the first).

## 1. Declaration

In a compose manifest (`~/.config/dctl/devcontainer/<name>.yaml`), beside `layers`:

```yaml
layers:
  - base
  - nix
providers:
  - name: dctl-nix-store
    required: true   # default; false degrades every failure to a warning
```

- `name` is a bare executable name (`^[A-Za-z0-9._-]+$`) resolved on the host PATH — never a path, so the manifest stays machine-independent.
- Providers run in manifest order.
- Providers are a property of the **manifest**, not of a project or a layer: an explicit config (`--config`, `DCTL_CONFIG`) bypasses the manifest and therefore bypasses providers with it.
- Schema: `schemas/compose.schema.yaml`; fallback validation in `lib/dctl/config.sh` mirrors it when `check-jsonschema` is absent.

## 2. Invocation contract

dctl invokes each provider as:

```text
<name> <phase> --workspace <absolute workspace path> --project <canonical project name>
```

| Phase     | When dctl calls it                          | dctl consumes                     |
| --------- | ------------------------------------------- | --------------------------------- |
| `prepare` | Before `devcontainer up` (`ws up`, `ws reup`, the `dctl test` smoke up) | stdout JSON → `--mount` / `--remote-env` args |
| `attach`  | Before every `devcontainer exec` (`ws exec/shell/run`, the smoke exec)  | stdout JSON → `--remote-env` args (mounts are ignored by the CLI at exec time; emit none) |
| `release` | After `ws down` removes the containers      | exit code only (warn-only)        |
| `check`   | During `dctl test`                          | exit code → PASS/FAIL row (a failing check on an optional provider degrades to a warning) |

A provider must accept all four phases; a phase with nothing to do answers `{}` (or nothing) and exits 0. Unknown future phases should exit non-zero with a message rather than guessing.

### 2.1 The answer

stdout is a single JSON object; empty stdout means "nothing to add":

```json
{
  "mounts": ["type=bind,source=/run/foo,target=/run/foo,readonly"],
  "remoteEnv": {"FOO_DIR": "/run/foo"}
}
```

- `mounts`: strings in docker `--mount` syntax, passed to `devcontainer up --mount` verbatim — but dctl composes the argv itself; a provider never emits raw CLI flags, so a provider cannot smuggle arbitrary options into the invocation.
- `remoteEnv`: string-to-string; each pair becomes `--remote-env K=V`.
- Anything else in the object is rejected as malformed today; extend this spec before extending the shape.
- stderr passes through to the user — it is the provider's progress/warning channel.

### 2.2 Error policy

The forge-seed policy, made explicit per declaration:

- `required: true` (default): a missing executable, a non-zero exit, or a malformed answer **aborts** the lifecycle command. Use for providers whose absence bricks the container (a mount source that must exist).
- `required: false`: the same failures degrade to a warning and the provider is skipped — the container starts degraded, like running without forge auth.
- `release` is always warn-only: `ws down` must never fail on a provider. It must also be idempotent and cheap when there is nothing to release, because dctl calls it whenever a workspace lifecycle ends — `ws down` with containers, `ws down` with none left (a failed `up` may have prepared host state and created nothing), and the `dctl test` smoke cleanup.

### 2.3 Lifecycle asymmetry (normative)

`prepare` may do expensive, host-mutating work: mount, seed, snapshot, refresh. `attach` runs on **every exec** and must be cheap and idempotent — and must never invalidate state a running container depends on. The two existing contracts mark the two ends: forge-seed re-seeds credentials at attach time on purpose (rotation propagates through the live bind); a store provider must **not** remount at attach time, because changing a mount under a running container is exactly the hazard it exists to manage. When in doubt, make `attach` a no-op and put the work in `prepare`.

`check` is read-only diagnosis: it must not mutate host state, and its exit code is the whole answer.

## 3. What providers are not

- Not layers: a layer is declarative devcontainer.json content merged by `lib/dctl/config.sh`; a provider is host-side behavior. A feature usually needs both — static mounts and env in a layer, lifecycle in a provider — and the manifest is where they pair.
- Not a plugin API inside dctl's process: providers are separate executables with a stdout contract, testable in isolation, owned outside this repo.
- Not a secrets channel: values in `remoteEnv` land in process environments. Secrets travel as files per the secret-forwarding SPEC.

## 4. Implementation map

- `lib/dctl/providers.sh` — manifest reading, invocation, JSON validation, argv composition (`collect_provider_args`, `provider_release_all`).
- `lib/dctl/ws.sh` — `prepare` at up/reup, `attach` in `devcontainer_exec`, `release` in down.
- `lib/dctl/test.sh` — `run_provider_checks` (one row per declared provider) and provider args on the smoke up/exec.
- `tests/providers_test.bats` — the contract under mocks.
- Follow-up, deliberately not done yet: refolding `collect_git_worktree_mounts` and the forge-auth collectors into internal providers of this same shape.
