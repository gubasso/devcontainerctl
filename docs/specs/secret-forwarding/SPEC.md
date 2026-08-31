# Secret Forwarding — The forge-auth Convention

> Status: Implemented
> Scope: How host-held secrets and credentials reach a dctl sandbox — and how they must not.
> Audience: Maintainers, contributors, and authors of other sandbox tooling that wants to consume the same contract.
> Companion: [../sandbox-runtime/SPEC.md](../sandbox-runtime/SPEC.md) — the threat model this convention answers (§3.1, §5.1).

## 0. Purpose

A sandbox running AI agents must be able to use forge CLIs (`gh`, `glab`) and git transports without a long-lived credential ever living inside it. This document specifies the convention dctl uses: a host-side seeder materializes short-lived credential files into tmpfs, and the sandbox consumes them at a fixed path. It is the same pattern the wider ecosystem converged on for plain-container runtime secrets (Vault Agent templates, sops-nix, systemd `LoadCredential`): **files in a tmpfs directory at a conventional path, with tight permissions — never environment variables, never argv.**

## 1. Non-goals and rejected transports

- **Environment variables** (`GH_TOKEN` via `--remote-env`, `${localEnv:...}`, or the Dev Container spec's secrets support): rejected. An env token is readable in `/proc/*/environ` of every process in the sandbox and leaks into diagnostics. Removing exactly this exposure is why the convention exists.
- **Docker BuildKit secrets**: build-time only; dctl uses them correctly for image builds (`lib/dctl/image.sh`), but they have no runtime story.
- **Swarm/Compose `secrets:`**: Swarm-only, or (outside Swarm) sugar over the same host-file bind this convention already makes — with a static plaintext source file and no re-seed.
- **Mounting the keyring's D-Bus socket**: would hand every sandbox the entire Secret Service. Never do this.

## 2. The contract

Three lines, and anything that can bind-mount a directory can consume it — dctl, a bare `devcontainer.json`, podman, a CI job:

1. Host side: `forge-seed --scope <name>` (idempotent, exit 0; `--print-dir` emits the seed dir path).
2. Runtime: bind-mount the seed dir at `/run/forge-auth`.
3. Sandbox: `GH_CONFIG_DIR=/run/forge-auth/gh`, `GLAB_CONFIG_DIR=/run/forge-auth/glab-cli`.

### 2.1 Seeder responsibilities (`forge-seed`, owned by the user's host config)

- Long-lived credentials stay in the OS keyring; the seeder reads them through the keyring-aware host CLIs (`gh auth token`, `glab config get token --host`).
- The seed root is `${FORGE_SEED_ROOT:-$XDG_RUNTIME_DIR/forge-auth}` — tmpfs-backed, cleared at logout. Directories are `0700`, files `0600`.
- Each `--scope` is an isolated seed; a scope is one path segment (a project name, `ci`, ...).
- gh: token written at both the top level and `users.<login>` of the seeded `hosts.yml` (version-proof across gh 2.40). glab: the host `config.yml` is copied — not synthesized, which is what preserves `is_oauth2` — then `use_keyring` is forced off and `oauth2_expiry_date` stripped, so the sandbox reads the token from the file and never attempts a refresh it cannot perform.
- Warn-don't-fail: past argument validation, every problem degrades to a warning and the consumer runs unauthenticated for that forge.

### 2.2 Consumer lanes

- **dctl (this repo, `lib/dctl/auth.sh`)**: calls the seeder at `up`, `reup`, and **every `exec`** — the re-seed is the token-rotation path, because the seed dir is a live bind and an updated file reaches an already-running container immediately. dctl scopes by `resolve_canonical_project_name`, and degrades to a warning when `forge-seed` is absent (optional runtime dependency, like `yq`).
- **Bare devcontainer.json (no dctl)**: `"initializeCommand": ["forge-seed", "--scope", "${localWorkspaceFolderBasename}"]` plus a static string mount of `${localEnv:XDG_RUNTIME_DIR}/forge-auth/${localWorkspaceFolderBasename}` and the two `containerEnv` paths. Trade-offs: seeding happens only at `up` (long-lived containers need a reup after token expiry), and the scope is the folder basename, not dctl's canonical name. dctl-managed projects must NOT use `initializeCommand` for seeding — dctl's layer merge is last-wins for that key, and dctl already re-seeds itself.
- **Anything else**: `podman run -v "$(forge-seed --scope ci --print-dir)":/run/forge-auth ...`, a CI job, a future runtime backend. Same three lines.

### 2.3 What stays outside the contract

- **SSH agent forwarding** is a dctl feature, not part of forge-seed: dctl mounts the host's live `SSH_AUTH_SOCK` (the socket, never key material) at `/run/dctl/ssh-agent.sock`, gated on the socket actually existing so the variable and the socket are always both present or both absent.
- **Image-build tokens** travel as BuildKit secrets, never through this convention.

## 3. Threat model position

Honestly stated: this convention removes the environment exposure, the host at-rest plaintext exposure, and the sandbox's write access to host config. It does not make a live token unstealable — a token the sandbox can use is a token an in-sandbox agent can read at `/run/forge-auth` and exfiltrate over open egress (sandbox-runtime SPEC §3.1). Egress control is the complementary mitigation, not this convention's job.

## 4. Extension guidance

A new secret class joins the convention as a new scope or a new subdirectory of a scope, seeded by the same tool with the same rules: keyring or single-owner host file as the source, tmpfs target, `0700`/`0600`, warn-don't-fail, sandbox reads a path. The still-open `~/.claude*` mounts named in sandbox-runtime SPEC §5.1 are the natural next tenant.
