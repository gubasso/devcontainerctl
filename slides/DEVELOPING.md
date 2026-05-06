# Developing the slides

Cheatsheet for authoring and building the presentation locally.

## One-time setup

```bash
cd slides
npm install
```

Requires Node LTS (the repo's `mise.toml` pins `node = "latest"`; run
`mise install` from the repo root if mise is configured).

## Author with hot reload

```bash
npm run dev          # http://localhost:3030
```

Edit any file under `slides/`; the browser hot-reloads on save.

## Project layout

| Path               | Purpose                                                                                          |
| ------------------ | ------------------------------------------------------------------------------------------------ |
| `slides.md`        | Main deck. Front matter at top configures theme, layout, transitions. Slides separated by `---`. |
| `pages/*.md`       | Imported sub-decks. Reference from `slides.md` with `<<< ./pages/imported-slides.md`.            |
| `components/*.vue` | Reusable Vue components. Use directly in markdown: `<Counter />`.                                |
| `snippets/*.ts`    | External code samples. Embed with `<<< @/snippets/external.ts`.                                  |
| `public/`          | Static assets served at `/` (create as needed).                                                  |
| `dist/`            | Build output (gitignored).                                                                       |

Full reference: <https://sli.dev/custom/directory-structure>.

## Common authoring tasks

- **New slide**: add `---` then your markdown.
- **Slide layout**: set `layout:` in slide front matter (`cover`, `two-cols`, `image-right`, …). See <https://sli.dev/builtin/layouts>.
- **Speaker notes**: add an HTML comment at the end of a slide:
  ```markdown
  <!-- presenter note here -->
  ```
- **Code block with line highlights**:
  ````markdown
  ```ts {2,4-6}
  // highlighted lines
  ```
  ````
- **Transitions, click animations, MDC syntax**: see <https://sli.dev/guide/syntax>.

## Build and preview production output

```bash
npm run build                              # local base, output to dist/
npm run build -- --base /devcontainerctl/  # match GH Pages deploy
npx serve dist                             # preview the built SPA
```

The CI workflow always passes `--base /devcontainerctl/`; locally you can omit
it unless verifying the deployed asset paths.

## Export to PDF or PNG

```bash
npm run export                  # dist/slides-export.pdf
npm run export -- --format png  # one PNG per slide
```

Requires Playwright; on first run Slidev will prompt to install Chromium.

## Useful flags

- `npm run dev -- --remote` — expose the dev server on the LAN for a phone preview.
- `npm run dev -- --port 4000` — change the port.
- `npm run dev -- --open=false` — start the dev server without auto-opening a browser tab (the `dev` script passes `--open`, so override with `=false` rather than `--no-open`).
- `slidev build --without-notes` — strip presenter notes from the published bundle.

## Resources

- Slidev guide: <https://sli.dev/guide/>
- Markdown syntax extensions: <https://sli.dev/guide/syntax>
- Theme gallery: <https://sli.dev/themes/gallery>
- Component reference: <https://sli.dev/builtin/components>
