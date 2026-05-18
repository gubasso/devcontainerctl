# Development workflow

How to build, run, and test `dctl` from a working tree without
disturbing an existing host install.

## TL;DR

Set `DCTL_HOME` and run the repo's `./bin/dctl` — config/cache live in
the sandbox, seed data is auto-detected from the working tree:

```bash
cd /path/to/devcontainerctl
export DCTL_HOME=$PWD/.dctl-dev

./bin/dctl doctor
./bin/dctl init
./bin/dctl image build agents
./bin/dctl ws up

# cleanup (production state is never touched)
rm -rf "$HOME/.dctl-dev"
```

Details below.

## Layout recap

`dctl` is a Bash dispatcher (`bin/dctl`) plus a library tree under
`lib/dctl/`. The entrypoint resolves its library directory relative to
its own location (`bin/dctl:6`):

```bash
DCTL_LIB_DIR="$(dirname "$(readlink -f "$0")")/../lib/dctl"
```

So invoking the repo's `./bin/dctl` always loads the repo's
`lib/dctl/`; no install step, no rebuild, edits are picked up on the
next invocation.

Install paths (used by `make install`, not the dev workflow) are
controlled by Make variables (`Makefile:1-4`):

| Variable      | Default                                | Purpose                          |
|---------------|----------------------------------------|----------------------------------|
| `BIN_DIR`     | `$HOME/.local/bin`                     | `dctl` entrypoint                |
| `LIB_DIR`     | `$HOME/.local/lib/dctl`                | Library tree                     |
| `DATA_DIR`    | `$HOME/.local/share/dctl`              | Images, devcontainers, schemas   |
| `SYSTEMD_DIR` | `$HOME/.local/share/systemd/user`      | Image rebuild timer/service      |

## Dev workflow — isolated sandbox via `DCTL_HOME`

The supported way to run `dctl` from a working tree is with `DCTL_HOME`
set. This redirects config, cache, and seed-data roots under one
prefix, so dev iteration cannot disturb the installed `dctl`'s state.
No install step.

When `DCTL_HOME` is set, `lib/dctl/_lib/paths.sh` redirects three
roots:

| Var               | Default under `DCTL_HOME`              | Replaces                  |
|-------------------|----------------------------------------|---------------------------|
| `DCTL_CONFIG_DIR` | `$DCTL_HOME/config`                    | `~/.config/dctl/`         |
| `DCTL_CACHE_DIR`  | `$DCTL_HOME/cache`                     | `~/.cache/dctl/`          |
| `DCTL_DATA_DIR`   | repo root (auto-detect) or `$DCTL_HOME/share` | `~/.local/share/dctl/` |

`DCTL_DATA_DIR` is the seed-data root that `IMAGES_DIR`,
`DEVCONTAINERS_DIR`, and `DCTL_SCHEMAS_DIR` derive from. Its default
auto-detects: when `./bin/dctl` runs from a repo working tree (the
parent of `lib/dctl/` contains `images/`, `devcontainers/`, and
`schemas/`), `DCTL_DATA_DIR` resolves to that repo root, so `dctl init`
seeds from there without `make install`. Outside a repo (e.g. an
installed `dctl`), it falls back to `$DCTL_HOME/share`.

So this is all you need from the repo:

```bash
export DCTL_HOME=$HOME/.dctl-dev
./bin/dctl init
./bin/dctl image build agents
./bin/dctl ws up
```

Override the auto-detect by setting `DCTL_DATA_DIR` explicitly, e.g.
`DCTL_DATA_DIR=$HOME/.dctl-dev/share` to use a populated install tree
under the sandbox instead of the repo.

Precedence (highest → lowest): individual `DCTL_*_DIR` / `IMAGES_DIR`
override → `DCTL_HOME` derivation (with auto-detect for data) →
`XDG_*` → `$HOME`. Override one knob without losing the others.

Caveats:

- Podman image storage is user-level and is NOT isolated by
  `DCTL_HOME`. If you need a parallel image, use a distinct image tag
  on the branch.
- Systemd units installed via `make install-systemd` hardcode
  `$(BIN_DIR)/dctl` and are also not affected by `DCTL_HOME` — testing
  the timer wiring requires a real `make install`.

Cleanup is one `rm -rf`:

```bash
rm -rf "$HOME/.dctl-dev"
```

Production state under `~/.config/dctl/`, `~/.cache/dctl/`, and
`~/.local/share/dctl/` is never touched.

## Running tests and gates

The Makefile drives the full test and lint surface; nothing here
depends on whether `dctl` is installed.

```bash
make test-unit          # bats: unit-tagged
make test-integration   # bats: integration-tagged
make test               # both
make lint               # shellcheck, shfmt, shellharden, bashate
make check              # full pre-commit + shellcheck -x + shfmt -d + bats + check-no-docker
```

Other gates worth knowing about:

- `make check-no-docker` — fails on stray `docker`/`Dockerfile` strings
  outside the whitelist (`Makefile:159-171`).
- `make gate-no-eval` — fails on un-annotated `eval` (`Makefile:173-174`).
- `make gate-no-raw-ansi` — opt-in (`DCTL_ENFORCE_ANSI_GATE=1`).
- `make gate-one-public-fn-per-file` — opt-in (`DCTL_ENFORCE_ONEFN_GATE=1`).

Pre-commit hooks (`shellcheck`, `shfmt`, `shellharden`, `bashate`) run
on `git commit`; run `make check` before pushing to catch the same
issues locally.

## See also

- [INSTALL.md](INSTALL.md) — host-package preflight (libkrun, rootless Podman).
- [QUICKSTART.md](QUICKSTART.md) — shortest end-to-end path for an end user.
- [ARCHITECTURE.md](ARCHITECTURE.md) — runtime/adapter model.
- [CLAUDE.md](../CLAUDE.md) — repo invariants and orientation.
