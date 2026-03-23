# dctl Design Specs

These documents are design documents for future implementation in `devcontainerctl`.
They describe planned behavior, file layouts, and integration points in enough detail
for an implementer to work from them. They are not a description of current runtime
behavior unless a section explicitly says so.

## As-Is Reference

Current implemented behavior is documented in
[`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md). Treat that document as the
"as-is" reference and the files in this directory as the "to-be" design set.

## Glossary

- **workspace**: The current project directory from which `dctl` is invoked. In the
  current codebase this is `WORKSPACE_FOLDER`, derived from `$PWD`.
- **work-clone**: A sibling clone whose basename contains a suffix after the first
  `.` character, such as `repo.42-add-auth`, typically used for parallel feature work.
- **main repo**: The sibling directory whose basename matches the portion of the
  work-clone name before the first `.`, such as `repo/` for `repo.42-add-auth/`.
- **canonical project**: The stable project identity used for host-side registry
  lookups. All work-clones of the same repository map to the same canonical project.
- **config source**: Any source that can provide a `devcontainer.json`, such as a
  CLI flag, environment variable, project registry entry, local file, discovered
  sibling, or user default. Dockerfile sources use a narrower model scoped to
  `dctl image build` (see `40-dockerfile-hierarchy.md`).
- **resolution chain**: The ordered precedence list that `dctl` evaluates to decide
  which config source wins for `devcontainer.json` resolution.

## Spec Set

| File | Description | Status |
| --- | --- | --- |
| [`00-resolution-model.md`](./00-resolution-model.md) | Shared precedence model, XDG layout, path normalization, and sibling discovery rules. | Draft |
| [`10-project-registry.md`](./10-project-registry.md) | Per-project YAML registry, canonical name derivation, and JSON Schema validation. | Draft |
| [`20-devcontainer-resolution.md`](./20-devcontainer-resolution.md) | `devcontainer.json` lookup algorithm and command integration rules. | Draft |
| [`30-templates.md`](./30-templates.md) | Template categories, defaults, discovery order, and `dctl init` changes. | Draft |
| [`40-dockerfile-hierarchy.md`](./40-dockerfile-hierarchy.md) | User-overridden versus installed Dockerfile resolution for managed images. | Draft |
| [`90-implementation-impact.md`](./90-implementation-impact.md) | Mapping from approved design to code changes and sequencing. | Draft |
| [`99-acceptance-criteria.md`](./99-acceptance-criteria.md) | Cross-cutting acceptance scenarios and non-regression expectations. | Draft |

## Status Meanings

- **Draft**: Written, but not yet approved for implementation.
- **Approved**: Reviewed and accepted as the basis for implementation.
- **Implemented**: Landed in code and reflected in user-facing behavior.

## Reading Order

1. Read [`00-resolution-model.md`](./00-resolution-model.md) first.
2. Then read [`10-project-registry.md`](./10-project-registry.md) and
   [`20-devcontainer-resolution.md`](./20-devcontainer-resolution.md).
3. Then read [`30-templates.md`](./30-templates.md) and
   [`40-dockerfile-hierarchy.md`](./40-dockerfile-hierarchy.md).
4. Finish with [`90-implementation-impact.md`](./90-implementation-impact.md) and
   [`99-acceptance-criteria.md`](./99-acceptance-criteria.md).
