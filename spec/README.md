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

## Spec Set

| File | Description | Status |
| --- | --- | --- |
| [`00-resolution-model.md`](./00-resolution-model.md) | Shared precedence model, XDG layout, path normalization, and sibling discovery rules. | Implemented |
| [`10-project-registry.md`](./10-project-registry.md) | Per-project YAML registry, canonical name derivation, and JSON Schema validation. | Implemented |
| [`20-devcontainer-resolution.md`](./20-devcontainer-resolution.md) | `devcontainer.json` lookup algorithm and command integration rules. | Implemented |
| [`30-templates.md`](./30-templates.md) | Template categories, defaults, discovery order, and `dctl init` behavior. | Implemented |
| [`40-dockerfile-hierarchy.md`](./40-dockerfile-hierarchy.md) | User-overridden versus installed Dockerfile resolution for managed images. | Implemented |
| [`45-devcontainer-metadata-extraction.md`](./45-devcontainer-metadata-extraction.md) | Historical record of moving shared config out of the image layer and into templates. | Implemented |
| [`90-implementation-impact.md`](./90-implementation-impact.md) | Mapping from approved design work to the landed code changes. | Implemented |
| [`99-acceptance-criteria.md`](./99-acceptance-criteria.md) | Cross-cutting acceptance scenarios and non-regression expectations. | Implemented |

## Status Meanings

- **Implemented**: Landed in code and reflected in user-facing behavior

## Reading Order

1. Read [`00-resolution-model.md`](./00-resolution-model.md) first.
2. Then read [`10-project-registry.md`](./10-project-registry.md) and
   [`20-devcontainer-resolution.md`](./20-devcontainer-resolution.md).
3. Then read [`30-templates.md`](./30-templates.md),
   [`40-dockerfile-hierarchy.md`](./40-dockerfile-hierarchy.md), and
   [`45-devcontainer-metadata-extraction.md`](./45-devcontainer-metadata-extraction.md).
4. Finish with [`90-implementation-impact.md`](./90-implementation-impact.md) and
   [`99-acceptance-criteria.md`](./99-acceptance-criteria.md).
