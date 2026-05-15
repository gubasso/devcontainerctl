# Phase 40 — Tier 0 hygiene + default-deny egress allowlist (prex task brief)

> Status: Pending
> Companion docs (Codex must read these in stage 1):
> - [docs/specs/sandbox-runtime/SPEC.md](../SPEC.md) (§3.1 token exfiltration, §5.1 Tier 0 hardening, §5.4 deferred Tier 3 cleanup, §7 Tier 0 acceptance, §8 open questions)
> - [docs/specs/sandbox-runtime/DECISION.md](../DECISION.md)
> - [docs/specs/sandbox-runtime/DECISION-LINUX.md](../DECISION-LINUX.md)
> - [docs/specs/sandbox-runtime/IMPLEMENTATION-PLAN.md](../IMPLEMENTATION-PLAN.md) (master overview)
> Reference: ai-agents-sandbox `:289-294` (tmpfs runArgs entry).
> Depends on: [`20-ws-and-image-adapter-rewire.md`](20-ws-and-image-adapter-rewire.md) — must be `Done`. `dctl ws` and `dctl image` run through `rt_*`; the cached devcontainer.json carries `--runtime krun` already.
> Output of this round: Tier 0 hygiene (no host /tmp bind, dropped caps, ephemeral token forwarding) is on the default path; a default-deny egress allowlist blocks unknown hosts inside the microVM.

## Task

Apply [SPEC.md §5.1](../SPEC.md) Tier 0 hardening that is runtime-agnostic but cheap, **and** land the default-deny egress allowlist that is the highest-impact mitigation against token exfiltration ([SPEC.md §3.1](../SPEC.md)). libkrun's TSI removes host-side TAP/bridge plumbing but does not apply outbound filtering; we own that ourselves.

This round combines what IMPLEMENTATION-PLAN.md called Phase 4 (Tier 0 mounts + caps + ephemeral tokens) and Phase 5 (egress allowlist) because they share devcontainer.json edit targets (`devcontainers/base/devcontainer.json`) and the same `_lib/auth/*` helper tree. The boundary is preserved in the subsections below so the round's diff stays reviewable. Contingency split: if stage 3 hits the timeout, split into `40a` (Phase 4) + `40b` (Phase 5).

## Preconditions (must already be true on `develop`)

- Round `20` is `Done`. `dctl ws` + `dctl image` are podman-only via `rt_*`. The cached `devcontainer.json` carries `--runtime krun` and the default krun resource annotations.
- The `lib/dctl/_lib/auth/` tree (`gh_token.sh`, `glab_token.sh`, `collect_env.sh`) exists from round 15a.
- `make check` is currently green on `develop`.

## Scope (in this round)

### Phase 4 work — Tier 0 hygiene (mounts, caps, ephemeral tokens)

1. **Drop host `/tmp` bind** in `devcontainers/base/devcontainer.json:27-30`. Replace with a tmpfs `runArgs` entry: `--tmpfs /tmp:rw,nosuid,size=1g` (matches ai-agents-sandbox `:289-294`).
2. **Add `--cap-drop=ALL` and `--security-opt=no-new-privileges`** to `runArgs` in `devcontainers/agents/devcontainer.json:107-111`. Verify Codex CLI's inner `bwrap` sandbox still starts. If it does not start, document the trade-off and move bwrap-dependent agents to an opt-in `agents-permissive` profile per [SPEC.md §5.1 item 5](../SPEC.md). The permissive seccomp profile (`devcontainers/agents/seccomp-bwrap.json`) and `apparmor=unconfined` become **non-load-bearing** under libkrun — leave them in place for now and document the deferred Tier 3 cleanup ([SPEC.md §5.4](../SPEC.md)).
3. **Replace host token bind-mounts with scoped ephemeral forwarding** — extend the helpers under `lib/dctl/_lib/auth/`:
   - **Remove** `~/.config/gh`, `~/.config/glab-cli` bind mounts from `devcontainers/base/devcontainer.json:17-26`.
   - **Remove** `~/.claude`, `~/.claude.json`, `~/.codex`, `~/.gemini` bind mounts from `devcontainers/agents/devcontainer.json:113-122`.
   - **Verify** `_lib/auth/gh_token.sh` / `_lib/auth/glab_token.sh` (extracted from `auth.sh:12-58` in round 15a) still forward the short-lived API token via env (`GH_TOKEN=…` / `GITLAB_TOKEN=…`); the env-forwarding path is unchanged from before round 15a but must be smoke-tested with the new adapter.
   - **Add** `lib/dctl/_lib/auth/ephemeral_creds.sh` (new file): for Claude / Codex / Gemini, write a copy of the minimal needed credential file into a per-session tmpdir under `$DCTL_CACHE_DIR/sessions/<workspace-hash>/`, mounted into the container as `ro`, torn down on `dctl ws down`.
4. **New file:** `docs/SECURITY.md` — document the new token-forwarding model: host config dirs are no longer bind-mounted; tokens flow via env vars (short-lived API tokens) or per-session ephemeral copies (Claude/Codex/Gemini session tokens) that live only for the workspace lifetime. Reference [SPEC.md §8](../SPEC.md) for the open question on Claude session-token export. Alternative if a separate doc is too heavy: append the same content as a §"Tier 0 hygiene & token forwarding" section to `docs/ARCHITECTURE.md`. Default to a new `docs/SECURITY.md`.
5. **`dctl ws down`** must clean the per-session tmpdir under `$DCTL_CACHE_DIR/sessions/<workspace-hash>/`. Add this to `commands/ws/down.sh`.

### Phase 5 work — Default-deny egress allowlist

1. **Create `lib/dctl/commands/net/`** — six files:
   - `commands/net/_default_allowlist.sh` — `net_default_allowlist()` returning the project default set: `api.anthropic.com`, `api.openai.com`, `*.googleapis.com`, `registry.npmjs.org`, `pypi.org`, `files.pythonhosted.org`, `crates.io`, `index.crates.io`, `download.opensuse.org`, `github.com`, `*.githubusercontent.com`, `gitlab.com`, `*.gitlab.io`, plus the workspace's git remotes auto-extracted from `git remote -v`.
   - `commands/net/_user_allowlist.sh` — `net_user_allowlist(workspace_folder)` reading the leaf `devcontainer.json` for a new `network.allow` key. (The schema entry lands in round 70; for this round, the key is read as an optional array; missing → empty.)
   - `commands/net/_compose.sh` — `net_compose_allowlist()` merging defaults + user list.
   - `commands/net/allow.sh` — `cmd_net_allow`. `dctl net allow <host>` appends to the leaf `devcontainer.json` allowlist and rebuilds the cached config.
   - `commands/net/show.sh` — `cmd_net_show` prints the effective list (defaults + user, with origin annotations).
   - `commands/net/_dispatch.sh` — `usage_net` + `main_net`.
2. **Egress enforcement mechanism** — **Option A (in-VM nftables)** is the chosen path:
   - Ship a small `dctl-egress` shell script (~50 LOC of generated nft rules) inside the microVM at boot. The script drops everything not in the allowlist.
   - Stage the script into the container image at build time (Phase 3's `rt_build` already handles this; just add the file to `images/agents/` or as a runtime-injected file mounted from `$DCTL_CACHE_DIR/`).
   - Boot the script via the lifecycle `postStartCommand` (lifecycle.sh from round 10 already runs it).
   - **Option B** (userspace HTTP/HTTPS proxy with `dctl-proxy` in Go/Rust) is **rejected for this round** — revisit if domain-list UX proves painful. Record this decision in `DECISION-LINUX.md`.
3. **CLI surface routing.** `bin/dctl` dispatch handles `dctl net …` automatically via `__dctl_dispatch` once `commands/net/_dispatch.sh` exists (round 15a's autoload primitives). No `bin/dctl` edit required.
4. **Default `network.allow` block in `devcontainers/base/devcontainer.json`** — add an empty array placeholder + a comment pointing at `dctl net allow <host>` for additions. The compose helper merges this with the defaults at cache-generation time.

## Out of scope for this round (DO NOT touch)

- `schemas/compose.schema.yaml` declaration of the `network.allow` / `runtime.resources` keys — round 70's job. This round uses the key without a formal schema; round 70 finalizes the schema.
- Dockerfile → Containerfile rename — round 70.
- The test additions for ephemeral-creds + net allowlist — round 60's job. This round can add smoke assertions inline if `tests/dctl_test.bats` already covers similar ground; do not create new test files.
- Phase 7 docs sweep (the broad `Docker`/`Dockerfile` removal) — round 70.
- A `dctl-proxy` binary (Option B) — explicitly rejected.

## Implementation guidance

### Ephemeral token forwarding shape

For Claude/Codex/Gemini, the on-host config dir typically contains credentials + cached chat history. We want to bind-mount **only the minimum needed credential file** (e.g. `~/.claude/credentials.json` or equivalent), not the whole dir. Per session:

```
$DCTL_CACHE_DIR/sessions/<sha1(workspace_folder)>/
├── claude-credentials.json   (cp from ~/.claude/credentials.json, ro)
├── codex-auth.json           (cp from ~/.codex/auth.json, ro)
└── gemini-key.json           (cp from ~/.gemini/key.json, ro)
```

Mounted into the container as `ro`. Removed by `dctl ws down`. Document the scoping decision in `docs/SECURITY.md`.

**Open question** (tracked in `docs/SECURITY.md`, not blocking): is there a published short-lived export path for Claude session tokens? If not, the per-session ephemeral copy is the best available mitigation until Anthropic ships one. Mirrors [SPEC.md §8](../SPEC.md).

### nftables ruleset shape

```
table inet dctl_egress {
  set allowlist {
    type ipv4_addr;
    flags interval;
    elements = { <resolved IPs of allowlist hosts> }
  }
  chain output {
    type filter hook output priority 0; policy drop;
    ct state established,related accept
    ip daddr @allowlist accept
    udp dport 53 accept  # DNS to host resolver; required for fresh resolution
    # else: drop (policy)
  }
}
```

Open question: domain allowlist vs IP allowlist. IP-based is simpler to enforce but wildcards (`*.googleapis.com`) need ongoing DNS resolution. Resolve at boot + every 5 min via cron-style refresh, or use a userspace DNS interceptor. **Recommendation:** start with IP-based, refresh every boot. If DNS churn breaks the model, revisit Option B (userspace proxy).

### `dctl net allow <host>` semantics

Appends the host to the leaf `devcontainer.json`'s `network.allow` array and triggers a cache regeneration. The host string format mirrors common allow-list conventions: bare hostname (`api.anthropic.com`), wildcard (`*.googleapis.com`), or CIDR (`192.168.1.0/24`). The compose helper normalizes.

### `commands/net/_dispatch.sh`

The dispatch pattern matches the other groups (`commands/ws/_dispatch.sh`, etc.). Reuse the autoload primitives from round 15a.

## Acceptance gates (all must pass before stage 4 review approves)

- `make check` passes (lint + bats + format).
- `dctl ws exec -- mount | grep '^.* on /tmp '` shows tmpfs, not a host bind.
- `dctl ws exec -- env | grep GH_TOKEN` shows the forwarded short-lived token.
- `dctl ws exec -- ls ~/.config/gh` is **empty** (no host bind-mount of the full config dir).
- For the agents profile: `dctl ws exec -- capsh --print | grep '^Current:'` shows empty caps (cap-drop=ALL worked) **and** `dctl ws exec -- cat /proc/self/status | grep NoNewPrivs` shows `NoNewPrivs: 1`.
- `dctl ws down` removes the container **and** the `$DCTL_CACHE_DIR/sessions/<workspace-hash>/` tmpdir.
- `dctl ws exec -- curl -sS https://attacker.example.com` is **blocked** by the egress allowlist (curl reports connection refused / timeout, not 200).
- `dctl ws exec -- curl -sS https://api.anthropic.com` succeeds (default allowlist accepts).
- `dctl net allow foo.example` appends to the leaf devcontainer.json and the cache is regenerated; `dctl net show` lists `foo.example`.
- `docs/SECURITY.md` exists and documents the token-forwarding model + the open Claude session-token question.

## Risks & known gotchas

- **bwrap-dependent agents** (Codex CLI) may fail with cap-drop=ALL. If so, document the trade-off and create the `agents-permissive` profile **in this round** rather than rolling back the default — the threat-model relaxation is the explicit decision recorded in [SPEC.md §5.1 item 5](../SPEC.md). The permissive profile carries `seccomp-bwrap.json` + `apparmor=unconfined`; default profiles do not.
- **In-VM nftables requires the microVM kernel to have nftables enabled.** libkrunfw's bundled kernel does include it (verified via the round-10 smoke), but if a future libkrunfw release drops it, the boot script must fail closed (not silently allow everything).
- **DNS-based allowlists drift.** Cloud SDKs frequently rotate IPs. The "refresh at boot" model means containers that run for days may accumulate stale entries. Document the limitation; recommend periodic restart for long-running agents.
- **`dctl net allow <host>` must validate input.** A user typing `dctl net allow ; rm -rf /` is unlikely but bash-escaping in the leaf JSON edit must be robust. Use `jq` for the append, not string concat.
- **The round 00 banner on `dctl test`** stayed on through round 20 (option b path) — if round 20 chose option (a), this round is unaffected; if option (b), `dctl test` is rewired in round 60.
- **`docs/SECURITY.md`** is permanent. Once it lives in `docs/`, treat it like any other architecture doc — Phase 7 (round 70) will audit it for `Docker`/`Dockerfile` references along with everything else.

## Plan-file cleanup (Codex must perform in stage 3, as part of the implementation commit)

1. Delete this file: `docs/specs/sandbox-runtime/plans/40-tier0-hygiene-and-egress.md`.
2. Update `docs/specs/sandbox-runtime/plans/README.md`: this round's row `Status` → `Done — <commit-sha> — <date>`.
3. Promote durable content:
   - `docs/SECURITY.md` is the permanent home for the token-forwarding model + the open Claude session-token question.
   - The egress-enforcement decision (Option A in-VM nftables; Option B rejected) goes into `docs/specs/sandbox-runtime/DECISION-LINUX.md`.
   - The `agents-permissive` profile rationale (if created) goes into `docs/SECURITY.md`.
4. Update `docs/specs/sandbox-runtime/IMPLEMENTATION-PLAN.md`: tick the Phase 4 + Phase 5 rows in the `## Per-round briefs` section.
