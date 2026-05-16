# CLAUDE.md — lib/dctl

Shell implementation for `dctl`.

Round 15a introduced the `_lib/` helper tree and lazy dispatch bootstrap.
Round 15b adds the `commands/` tree and removes the flat compatibility shims.

## What / Where

| What | Where |
|---|---|
| Dispatcher bootstrap | `bin/dctl` |
| Internal helpers | `lib/dctl/_lib/<topic>/<name>.sh` |
| Eager helper bootstrap | `lib/dctl/_lib/source.sh`, `_lib/log.sh`, `_lib/paths.sh` |
| Command tree | `lib/dctl/commands/{ws,image,init,deploy,config,test,doctor}/` |
| Runtime adapter | `lib/dctl/runtime/{common,krun}.sh` |
| Lifecycle interpreter | `lib/dctl/lifecycle.sh` |

## Naming

- Helper filename = function name.
- Command filename = verb name.
- Files starting with `_` are private to their directory.
- `__` prefix is internal-only; plain names are exported helper APIs.
- One function per helper file is the default rule.
- Blessed exceptions:
  - `_lib/source.sh` groups `__dctl_require`, `__dctl_autoload_register`, `__dctl_dispatch`.
  - `_lib/log.sh` groups `log`, `warn`, `err`, `require_cmd`.
  - `_lib/paths.sh` groups XDG state and path-printer helpers.

## Sourcing Model

- `bin/dctl` eagerly loads only `_lib/source.sh`, `_lib/log.sh`, and `_lib/paths.sh`.
- All other helpers load through `__dctl_require`.
- `__dctl_dispatch` short-circuits `help`, `--help`, `version`, `--version`, and no-arg entry before loading any command group.
- Round 15b removed the flat fallback; `__dctl_dispatch` routes only to `commands/<group>/_dispatch.sh`.

## Size Guidance

- Soft target: about 200 lines per file.
- Hard ceiling: 500 lines per file.
- Small helper files are allowed when they preserve the one-function-per-file layout adopted in 15a.
- `tests/structure_test.bats` enforces the command-tree layout, the 500-line ceiling, and the `_lib` one-function rule with exemptions for `_lib/source.sh`, `_lib/log.sh`, and `_lib/paths.sh`.

## Command Groups

- Round 15b groups: `ws`, `image`, `init`, `deploy`, `config`, `test`, `doctor`
- Round 40 adds: `net`

## Do Not Move

- `lib/dctl/runtime/common.sh`
- `lib/dctl/runtime/krun.sh`
- `lib/dctl/lifecycle.sh`

Those files stay flat until a second runtime backend lands or `lifecycle.sh` grows enough to justify a split.
