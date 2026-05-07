# `devcontainerctl` — principles and rules

This is the spec the repo follows. Use it as the authority when deciding
how a new feature, refactor, or bug fix should be shaped.

Source specs (read-only references):

- Bash CLI conventions:
  `~/.dotfiles/_docs/development/languages/bash/bash-cli-project-specs-overview.md`
- LLM-agent CLI design:
  `~/.dotfiles/_docs/development/practices/designing-cli-tools-for-llm-coding-agents.md`

When this file conflicts with the sources above, prefer the source.

---

## 1. Project layout

- `bin/dctl` is a shim. No business logic — only strict-mode setup,
  symlink resolution, and `source lib/dctl/core.sh; dctl::core::main "$@"`.
- `lib/dctl/` holds the library:
  - `core.sh` — `main()` and dispatch.
  - `loader.sh` — `dctl::loader::require <ns> <name>` lazy sourcing.
  - `common.sh` — log/die/colorize/paths.
  - `commands/cmd_<name>.sh` — one public function per file: `dctl::cmd::<name>`.
  - `functions/fn_<name>.sh` — one private helper per file: `dctl::fn::<name>`.
- `completions/` ships bash, zsh, fish completion files.
- `man/dctl.1.scd` is the scdoc source; `make man` builds `dctl.1`.
- `test/` holds bats tests, one `.bats` per command, mirroring
  `lib/dctl/commands/`. Helpers under `test/test_helper/` are git
  submodules (`bats-support`, `bats-assert`, `bats-file`).
- `schemas/` versions JSON output schemas.
- `install.sh` / `uninstall.sh` are the install surface; the Makefile
  delegates to them.

## 2. Module conventions

- **One public function per file** in `commands/` and `functions/`.
- **All functions are namespaced** as `dctl::<ns>::<name>`. No bare names.
- File-scoped private helpers are prefixed `__` and are not namespaced.
- Every `lib/` file carries a `desc:` sentinel on line 2:
  `: 'desc: <one-line description>'`.
- The loader is lazy: `bin/dctl` startup touches only `core.sh`,
  `loader.sh`, and `common.sh`. Everything else is sourced on demand
  through `dctl::loader::require`.
- If `$XDG_CONFIG_HOME/dctl/conf.d/*.sh` exists, it is sourced (in
  lexical order) after `common.sh` and before dispatch.

## 3. Strict mode

Every executable bash file starts with:

```bash
#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit failglob nullglob lastpipe 2>/dev/null || true
IFS=$'\n\t'
```

Library files (sourced, not executed) omit the shebang but still set
`IFS` and use the same idioms internally.

Symlink resolution is portable (a `while [[ -L ]]` loop). Do not use
`readlink -f`.

## 4. Logging, output, and color

- **Stream split is a hard rule:**
  - `stdout` carries data only — tables, JSON, names, paths.
  - `stderr` carries logs, progress, warnings, and errors.
- **Public log helpers** live in `common.sh`:
  - `dctl::log::info <msg>` — `[info]` to stderr.
  - `dctl::log::warn <msg>` — `[warn]` to stderr.
  - `dctl::log::err  <msg>` — `[err ]` to stderr; does **not** exit.
  - `dctl::log::debug <msg>` — only when `DCTL_LOG_LEVEL=debug` or
    `--verbose`; stderr.
  - `dctl::die <code> [--fix F] [--next N] <msg>` — the only exit path.
- **Color rule.** ANSI escapes are emitted only when **all** of:
  - the destination stream is a TTY,
  - `NO_COLOR` is unset/empty,
  - `--no-color` was not passed,
  - `DCTL_LOG_LEVEL` is not `json`.
- Raw `printf '\033[…'` is forbidden outside `common.sh`. The CI gate
  `gate-no-raw-ansi` enforces this once enabled.

## 5. Exit codes and errors

### Exit-code contract

| Code | Meaning |
| ---- | ------- |
| 0    | Success |
| 1    | Generic runtime error (last resort) |
| 2    | Usage error — unknown flag, missing required arg, bad invocation |
| 3    | Resource not found — project, image, container, config |
| 4    | Validation error — schema mismatch, bad input |
| 5    | External dependency failure — docker, devcontainer CLI, network |
| 6    | Permission error — not authorized, file perms, EUID |
| 7    | Precondition failed — already exists, already running, conflict |
| 8    | Timeout |
| 130  | SIGINT |
| 143  | SIGTERM |

`dctl::die <code>` is the only path to exit. `exit` is forbidden in
library functions; use `return N` or `dctl::die`.

### Three-part error format

```
[err ] <what happened>
       Fix:  <concrete action the user/agent can take>
       Next: <command to run, or "dctl help <group>">
```

`dctl::die` accepts `--fix` and `--next` flags to compose this.

### Traps and temp files

- Register cleanup before the first `mktemp`:
  ```bash
  local tmp; tmp=$(mktemp)
  trap 'rm -f "$tmp"' EXIT
  ```
- `EXIT`, `INT`, `TERM` all trigger cleanup. INT exits 130, TERM exits 143.
- Secret-bearing files: `umask 077` before `mktemp` (or `chmod 600`
  immediately after).
- All writes are atomic: `mktemp` then `mv`. Non-atomic writes are forbidden.

## 6. Argument parsing

- Every command supports `--help`/`-h`, `--json`, `--quiet`/`-q`,
  `--verbose`/`-v`, `--no-color`.
- Global flags accepted at any position before the subcommand:
  `--help`, `--version`, `--json`, `--quiet`, `--verbose`, `--no-color`,
  `--log-level=<level>`, `--config=<path>`, `--yes`.
- `--` terminates flag parsing; everything after is positional.
- Destructive commands (`ws down`, `image rm`, future `project rm`)
  accept `--dry-run` and `--yes`. Without `--yes` and on non-TTY stdin
  they exit 2 with an error pointing at `--yes`.

## 7. Agent-facing surface

### `dctl usage`

Dumps the entire subcommand tree, flags, and examples in one stream.
`--json` produces a parseable form. One file, no pagination, ~400 lines max.

### `dctl doctor`

Health check. Verifies bash version, required binaries, registry file
validity, docker daemon reachability, and write access to cache/config/
state dirs. Exit 0 on pass, 5 otherwise. `--json` matches
`schemas/doctor.schema.json`.

### `dctl schema <type>`

Prints the JSON schema for an output type from `schemas/`.
Example: `dctl schema ws-status`.

### `dctl verify <thing>`

Structured pass/fail for agent loops. `--json` is the default. Exit 0
on pass, 4 on fail. Output always includes `"ok": bool` and a
`"reasons": [...]` array when false.

### JSON output contract

- Every read-path command supports `--json`.
- JSON goes to stdout; logs stay on stderr. `cmd --json | jq .` must
  always work.
- One JSON document per invocation (object or array). No NDJSON unless
  documented.
- Every top-level object carries a `"schema"` field like
  `"ws-status@1"`. Schemas live in `schemas/` and are versioned;
  breaking changes bump the suffix.

### Pagination

List commands accept `--limit N` (default 50) and `--offset N`
(default 0). JSON output includes `"total"` and `"returned"`.

## 8. Config precedence

Resolution order (first wins):

1. Command-line flag
2. Environment variable (`DCTL_<UPPER_SNAKE>`)
3. Per-project registry entry (`projects.yaml`)
4. Global user config (`$XDG_CONFIG_HOME/dctl/config.yaml`)
5. Built-in default

Environment overrides for file locations: `DCTL_CONFIG_PATH`,
`DCTL_REGISTRY_PATH`, `DCTL_LIB_DIR`, `DCTL_CACHE_DIR`, `DCTL_STATE_DIR`.

Missing-config errors always name the env var **and** the file path the
user could set.

## 9. Install and packaging

- `install.sh` is PREFIX-overridable, XDG-aware, EUID-detecting, and
  writes `$XDG_DATA_HOME/dctl/install-manifest.txt`.
- `uninstall.sh` reads the manifest and removes the listed files.
- Makefile install targets delegate to the scripts. No hardcoded file
  lists in the Makefile.
- Completions install to `bash-completion/completions`,
  `zsh/site-functions`, `fish/vendor_completions.d`.
- Man page is built from `man/dctl.1.scd` via `make man`.
- `DCTL_VERSION` is injected at install time from
  `git describe --tags --always`.

## 10. Testing

- bats-core plus `bats-support`, `bats-assert`, `bats-file` as git
  submodules under `test/test_helper/`.
- One `.bats` file per command, mirroring `lib/dctl/commands/`.
- `test/test_helper/common-setup.bash` provides shared fixtures
  (`mock_docker`, `mock_devcontainer`, `tmp_registry`, ...).
- Integration tests are tagged `@integration` and run via
  `make test-integration`. `make test` (unit-only) must run offline
  with no docker daemon.
- Every error path has a test asserting the exact exit code.

## 11. Lint, format, CI

- `.shellcheckrc` declares `external-sources=true` and the
  `SCRIPTDIR`-relative source paths.
- `shfmt` canonical args are `-i 2 -ci -bn -s`.
- `.editorconfig` enforces 2-space indent for `.sh`, `.bats`, `.yaml`,
  `.json`.
- CI (`.github/workflows/ci.yml`) runs:
  - `shellcheck -x bin/* lib/dctl/**/*.sh`
  - `shfmt -d -i 2 -ci -bn -s bin/ lib/ hooks/ test/`
  - `bats -r test/` (unit; integration behind an env gate)
  - `pre-commit run --all-files`
  - the safety gates listed in §12.
- Target a bash matrix of 4.4 / 5.0 / 5.2 (per-job containers).
- `make check` is the local superset of the CI lint/test pipeline.

## 12. Safety bans

These are enforced by grep-based CI gates:

- No `eval` in `bin/`, `lib/`, or `hooks/`. Lines tagged
  `# allow-eval` are exempt.
- No raw ANSI escape sequences outside `lib/dctl/common.sh`.
- No more than one public function (`dctl::cmd::*` or `dctl::fn::*`)
  per file in `lib/dctl/commands/` or `lib/dctl/functions/`.
- No `find | while read`. Use `find -print0` plus `read -r -d ''`.
- No `exit` inside library functions — `dctl::die` or `return N` only.

Additional rules not gated by CI but reviewed in PR:

- User-controlled strings never enter `yq`/`jq` expressions without
  validation. Project names match `^[A-Za-z0-9._-]+$`.
- Secret-bearing temp files use `umask 077`.
- All writes are atomic (`mktemp` + `mv`).
- `--yes` is required for destructive ops on non-TTY stdin.

## 13. Verb-noun shape

All top-level invocations follow `dctl <group> <verb>`:

```
dctl ws      up|reup|down|exec|shell|run|status|list
dctl image   build|list|rm
dctl project init|deploy|list|rm
dctl config  get|set|list|path
dctl auth    login|logout|status
dctl doctor
dctl usage
dctl schema  <type>
dctl verify  <thing>
dctl help
dctl version
```

Legacy top-level verbs (`dctl init`, `dctl deploy`, `dctl test`) remain
as deprecated aliases that print a `[warn]` and forward to the new
paths. Removal target: one release after the rename.

## 14. Documentation

- `README.md` is user-facing only (install, quick example, links).
  Target under 200 lines.
- `docs/ARCHITECTURE.md` covers how the pieces fit; no user-facing content.
- `docs/QUICKSTART.md` is the human quickstart.
- `docs/AGENT-QUICKSTART.md` is one screen for LLM agents, ordered:
  (1) `dctl usage`, (2) `dctl doctor`, (3) always `--json`,
  (4) example flows.
- `AGENTS.md` (repo root) is cross-agent project context — points at
  `docs/`, `spec/`, and the external SKILL.md.
- `SKILL.md` lives outside this repo at `~/code/skills/dctl/` and is
  symlinked into `~/.claude/skills/dctl/` and `.agents/skills/dctl/`.
  It is **not** versioned here.
- `spec/` holds domain-model specs (separate from this CLI spec).

## 15. Commit and change discipline

- Conventional Commits. `git log` is the authoritative trail.
- Green at every commit: `make lint && make test` (and `make check`
  where the local toolchain allows).
- One logical change per commit. Batch only textually identical sweeps.
- Don't invent scope. If a refactor reveals a missing rule, update this
  spec in the same PR — don't silently expand the change.
