# dctl Design Specs

These documents now describe implemented behavior and the design record behind
it, not a future roadmap.

## As-Is Reference

[`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) is the high-level technical
guide. The files in this directory provide the corresponding implemented spec
set, terminology, and rationale for the current codebase.

## Glossary

- **workspace**: The current project directory from which `dctl` is invoked
- **work-clone**: A sibling clone whose basename contains a suffix after the
  first `.` character, such as `repo.42-add-auth`
- **main repo**: The sibling directory whose basename matches the portion of the
  work-clone name before the first `.`
- **canonical project**: The stable project identity used for host-side
  registry lookups
- **config source**: Any source that can provide a `devcontainer.json`
- **resolution chain**: The ordered precedence list that `dctl` evaluates
- **manifest**: A YAML file (e.g. `example.yaml`) declaring an ordered list of
  layers to compose into a single `devcontainer.json`. Validated by
  `schemas/compose.schema.yaml`
- **layer**: A directory containing a `devcontainer.json` that is referenced by
  a manifest's `layers` array (e.g. `base/`, `example/`)
- **leaf layer**: The last layer in a manifest — holds project-specific settings
- **shared layer**: Any non-leaf layer in a manifest — provides common
  infrastructure and can be listed by several manifests
- **user config**: `~/.config/dctl/`, which the user writes; `dctl` ships no
  image, no layer, and no manifest, and
  [`docs/examples/`](../docs/examples/README.md) shows a starting point

## Spec Set

| File | Description | Status |
| --- | --- | --- |
| [`00-resolution-model.md`](./00-resolution-model.md) | Shared precedence model, XDG layout, path normalization, and sibling discovery rules. | Implemented |
| [`10-project-registry.md`](./10-project-registry.md) | Per-project YAML registry, canonical name derivation, and JSON Schema validation. | Implemented |
| [`20-devcontainer-resolution.md`](./20-devcontainer-resolution.md) | `devcontainer.json` lookup algorithm and command integration rules. | Implemented |
| [`40-dockerfile-hierarchy.md`](./40-dockerfile-hierarchy.md) | User-config-only Dockerfile resolution for managed images. | Implemented |
| [`45-devcontainer-metadata-extraction.md`](./45-devcontainer-metadata-extraction.md) | Historical record of moving shared config out of the image layer and into devcontainer layers. | Implemented |
| [`90-implementation-impact.md`](./90-implementation-impact.md) | Mapping from approved design work to the landed code changes. | Implemented |
| [`99-acceptance-criteria.md`](./99-acceptance-criteria.md) | Cross-cutting acceptance scenarios and non-regression expectations. | Implemented |

## Status Meanings

- **Implemented**: Landed in code and reflected in user-facing behavior

## Reading Order

1. Read [`00-resolution-model.md`](./00-resolution-model.md) first.
2. Then read [`10-project-registry.md`](./10-project-registry.md) and
   [`20-devcontainer-resolution.md`](./20-devcontainer-resolution.md).
3. Then read [`40-dockerfile-hierarchy.md`](./40-dockerfile-hierarchy.md) and
   [`45-devcontainer-metadata-extraction.md`](./45-devcontainer-metadata-extraction.md).
4. Finish with [`90-implementation-impact.md`](./90-implementation-impact.md) and
   [`99-acceptance-criteria.md`](./99-acceptance-criteria.md).
