# CLAUDE.md — lib/dctl

Shell implementation for `dctl`.

Round 15a introduces the `_lib/` helper tree and lazy dispatch bootstrap.
The flat `*.sh` files remain as compatibility shims until round 15b.

## What / Where

| What | Where |
|---|---|
| Dispatcher bootstrap | `bin/dctl` |
| Internal helpers | `lib/dctl/_lib/<topic>/<name>.sh` |
| Eager helper bootstrap | `lib/dctl/_lib/source.sh`, `_lib/log.sh`, `_lib/paths.sh` |
| Command tree | `lib/dctl/commands/<group>/` in round 15b |
| Transitional flat shims | `lib/dctl/{common,auth,config,init,ws,...}.sh` |
| Runtime adapter | `lib/dctl/runtime/{common,krun}.sh` |
| Lifecycle interpreter | `lib/dctl/lifecycle.sh` |

## Naming

- Helper filename = function name.
- Command filename = verb name.
- Files starting with `_` are private to their directory.
- `__` prefix is internal-only; plain names are exported helper APIs.
- One function per helper file is the default rule.
- Blessed exceptions:
  - `_lib/log.sh` groups `log`, `warn`, `err`, `require_cmd`.
  - `_lib/paths.sh` groups XDG state and path-printer helpers.

## Sourcing Model

- `bin/dctl` eagerly loads only `_lib/source.sh`, `_lib/log.sh`, and `_lib/paths.sh`.
- All other helpers load through `__dctl_require`.
- `__dctl_dispatch` short-circuits `help`, `--help`, `version`, `--version`, and no-arg entry before loading any command group.
- Round 15a still falls back to the flat `lib/dctl/<group>.sh` modules when `commands/<group>/_dispatch.sh` is absent.
- Round 15b removes that fallback after the command tree exists.

## Size Guidance

- Soft target: about 200 lines per file.
- Hard ceiling: 500 lines per file.
- Small helper files are allowed when they preserve the one-function-per-file layout adopted in 15a.

## Compatibility Shims

- `common.sh`, `auth.sh`, `config.sh`, `init.sh`, and `ws.sh` now exist to `__dctl_require` moved helpers and preserve current entry points.
- Verb bodies stay in the flat files for 15a.
- Do not add new helper implementations back into the flat shims.

## Do Not Move In 15a

- `lib/dctl/runtime/common.sh`
- `lib/dctl/runtime/krun.sh`
- `lib/dctl/lifecycle.sh`

Those files are preserved verbatim in this round.
