# Sandbox Runtime — Specs and Decisions

The sandbox-runtime spec set for `devcontainerctl` (`dctl`): why this stack, what it is, what was decided, and the research that supports it.

## Layout

```
docs/specs/sandbox-runtime/
├── README.md                          ← you are here
├── spec.md                            ← foundation: premises, threat model, candidate set, tiers
├── decisions/                         ← committed, numbered decisions (read in order)
│   ├── 01-runtime-catalog.md          ← cross-platform catalog-level decision (Linux + macOS + CI fallback)
│   ├── 02-runtime-linux.md            ← narrowed Linux implementation: libkrun + crun --krun
│   └── 03-orchestration-native.md     ← dctl parses devcontainer.json natively (no @devcontainers/cli)
└── research/                          ← supporting investigations and comparisons
    ├── runtimes-catalog.md            ← per-option catalog with verdicts
    ├── libkrun-newline-bug.md         ← upstream bug investigation that gates #3
    ├── comparison-ai-agents-sandbox.md
    └── comparison-flake-pilot.md
```

## Reading order

- **First time:** [spec.md](spec.md) §1 (premises) and §3 (threat model). Then [decisions/02-runtime-linux.md](decisions/02-runtime-linux.md) for what was built, and [decisions/03-orchestration-native.md](decisions/03-orchestration-native.md) for how the orchestration layer above it works.
- **Cross-platform context:** [decisions/01-runtime-catalog.md](decisions/01-runtime-catalog.md).
- **Why not X?** [research/runtimes-catalog.md](research/runtimes-catalog.md) for per-option verdicts, plus [research/comparison-ai-agents-sandbox.md](research/comparison-ai-agents-sandbox.md) and [research/comparison-flake-pilot.md](research/comparison-flake-pilot.md) for two adjacent stacks evaluated in detail.
- **Why no `@devcontainers/cli`?** [research/libkrun-newline-bug.md](research/libkrun-newline-bug.md) for the upstream bug; [decisions/03-orchestration-native.md](decisions/03-orchestration-native.md) for the resulting commitment.

## Status

- [spec.md](spec.md) — Decided (§1–§4 authoritative; §5–§6 reflect the original tiered proposal, narrowed by the decisions in `decisions/`).
- [decisions/01-runtime-catalog.md](decisions/01-runtime-catalog.md) — Decided.
- [decisions/02-runtime-linux.md](decisions/02-runtime-linux.md) — Decided.
- [decisions/03-orchestration-native.md](decisions/03-orchestration-native.md) — Decided.
- [research/libkrun-newline-bug.md](research/libkrun-newline-bug.md) — Classified; upstream filing pending.
