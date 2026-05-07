# slides/

Slidev deck. Icons come from `unplugin-icons` and resolve only against the
`@iconify-json/*` packages actually installed in `package.json`.

## Installed icon sets

Only these sets are available — do **not** reference any other set (e.g.
`simple-icons:`, `devicon:`, `skill-icons:`); the build will fail with
`Icon <set>/<name> not found`.

- `carbon`
- `logos` (colored brand logos; many are dark-on-transparent and disappear on dark themes)
- `mdi` (monochrome — tint with `class="text-..."`)
- `ph` (Phosphor, monochrome)
- `svg-spinners`
- `vscode-icons` (file-type icons, colored — good fallback when a `logos:` icon is monochrome black)

To find what's available in an installed set:

```bash
node -e "const d=require('@iconify-json/<set>/icons.json'); \
  console.log(Object.keys(d.icons).filter(k=>k.includes('<query>')).join('\n'))"
```

## No click reveals

Do not use `v-click`, `v-clicks`, or any other click-based reveal directives in
`slides.md`. All slide content must render at once, with nothing gated behind
clicks or animations.

## Theme compatibility

The deck supports light and dark themes, so prefer icons that are visible on
both backgrounds:

- Colored brand icons → `logos:` if the icon has color baked in, otherwise
  `vscode-icons:file-type-*` (e.g. `vscode-icons:file-type-rust` instead of the
  black `logos:rust`).
- Monochrome icons → `mdi:` or `ph:` with an explicit `text-*` class.

Before adding a new icon, verify it exists in one of the installed sets above.
If a needed set is missing, add it to `package.json` rather than guessing a
name.
