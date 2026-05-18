# Development workflow

How to build, run, and test `dctl` from a working tree without disturbing
an existing host install.

## Layout recap

`dctl` is a Bash dispatcher (`bin/dctl`) plus a library tree under
`lib/dctl/`. The entrypoint resolves its library directory relative to
its own location (`bin/dctl:6`):

```bash
DCTL_LIB_DIR="$(dirname "$(readlink -f "$0")")/../lib/dctl"
```

That single line is what makes every option below work. As long as the
running script sits in a `bin/` directory whose sibling `lib/dctl/` is
populated, it picks up that library tree — repo, custom prefix, or
symlink target.

Install paths are controlled by Make variables (`Makefile:1-4`):

| Variable      | Default                                | Purpose                          |
|---------------|----------------------------------------|----------------------------------|
| `BIN_DIR`     | `$HOME/.local/bin`                     | `dctl` entrypoint                |
| `LIB_DIR`     | `$HOME/.local/lib/dctl`                | Library tree                     |
| `DATA_DIR`    | `$HOME/.local/share/dctl`              | Images, devcontainers, schemas   |
| `SYSTEMD_DIR` | `$HOME/.local/share/systemd/user`      | Image rebuild timer/service      |

Runtime config and cache live under XDG paths (`~/.config/dctl/`,
`~/.cache/dctl/`) and are written by `dctl init` / `dctl deploy` — they
are not affected by where the binary is installed.

## Option 1 — Run from the working tree

Zero install, zero collision with the existing `dctl`. The repo's
`bin/dctl` resolves to the repo's `lib/dctl/`.

```bash
cd /path/to/devcontainerctl
./bin/dctl doctor
./bin/dctl ws up
```

Use this for normal iterative development. The installed `dctl` on
`$PATH` is untouched.

Caveats:

- `make install-systemd` writes service files that hardcode
  `$(BIN_DIR)/dctl` (`Makefile:123-124`); the in-repo entrypoint is not
  registered with systemd unless you install it.
- `~/.config/dctl/` and `~/.cache/dctl/` are shared with the installed
  `dctl`. If a branch changes config schema or cache layout, point at a
  scratch home (e.g. `HOME=$PWD/.devhome ./bin/dctl ...`) to keep state
  isolated.

## Option 2 — Side-by-side install under a custom prefix

Install the branch under a separate prefix so both versions coexist on
`$PATH` under different paths. The binary name stays `dctl`; you
disambiguate by full path or by which prefix is earlier on `$PATH`.

```bash
make install \
  BIN_DIR="$HOME/.local-dev/bin" \
  LIB_DIR="$HOME/.local-dev/lib/dctl" \
  DATA_DIR="$HOME/.local-dev/share/dctl"

# invoke explicitly
"$HOME/.local-dev/bin/dctl" doctor
```

Uninstall the dev copy:

```bash
make uninstall \
  BIN_DIR="$HOME/.local-dev/bin" \
  LIB_DIR="$HOME/.local-dev/lib/dctl" \
  DATA_DIR="$HOME/.local-dev/share/dctl"
```

Pass the same variables to every `make install`/`make uninstall` pair —
the targets do not remember them.

## Option 3 — Alternate binary name (`dctl-dev`)

If you want the dev version on `$PATH` under a distinct name, install
under a custom prefix (Option 2) and rename the entrypoint. No script
edit needed — `DCTL_LIB_DIR` is computed from the file's actual location
via `readlink -f`, so a renamed file still resolves the correct sibling
`lib/dctl/`.

```bash
make install \
  BIN_DIR="$HOME/.local-dev/bin" \
  LIB_DIR="$HOME/.local-dev/lib/dctl" \
  DATA_DIR="$HOME/.local-dev/share/dctl"

mv "$HOME/.local-dev/bin/dctl" "$HOME/.local-dev/bin/dctl-dev"
ln -s "$HOME/.local-dev/bin/dctl-dev" "$HOME/.local/bin/dctl-dev"

dctl-dev doctor
```

Or skip the install entirely and symlink straight to the working tree.
`readlink -f` follows the symlink, so `DCTL_LIB_DIR` resolves to the
repo's `lib/dctl/`:

```bash
ln -s /path/to/devcontainerctl/bin/dctl "$HOME/.local/bin/dctl-dev"
dctl-dev doctor
```

The symlink form means every edit in the working tree is visible to
`dctl-dev` on the next invocation — no rebuild step.

## Choosing between the options

| Use case                                                     | Option |
|--------------------------------------------------------------|--------|
| Run a one-off check on the branch                            | 1      |
| Hack iteratively, see edits immediately                      | 1 or 3 (symlink) |
| Compare branch vs. installed `dctl` from two terminals       | 2      |
| Put the branch on `$PATH` under a memorable name             | 3      |
| Test the systemd image-build timer wiring                    | 2      |

## Running tests and gates

The Makefile drives the full test and lint surface; nothing here depends
on whether `dctl` is installed.

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

## Cleaning up

When you are done with the branch, remove only the dev install — never
touch the production prefix:

```bash
# Option 2/3 cleanup (custom prefix)
make uninstall \
  BIN_DIR="$HOME/.local-dev/bin" \
  LIB_DIR="$HOME/.local-dev/lib/dctl" \
  DATA_DIR="$HOME/.local-dev/share/dctl"

# Option 3 symlink cleanup
rm -f "$HOME/.local/bin/dctl-dev"
```

`~/.config/dctl/` and `~/.cache/dctl/` are shared user state and are not
removed by `make uninstall`; clear them manually only if the branch
left incompatible content behind.

## See also

- [INSTALL.md](INSTALL.md) — host-package preflight (libkrun, rootless Podman).
- [QUICKSTART.md](QUICKSTART.md) — shortest end-to-end path for an end user.
- [ARCHITECTURE.md](ARCHITECTURE.md) — runtime/adapter model.
- [CLAUDE.md](../CLAUDE.md) — repo invariants and orientation.
