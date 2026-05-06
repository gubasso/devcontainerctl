# Updating the slides

Cheatsheet for editing and publishing the presentation.

## Edit and preview locally

```bash
cd slides
npm install              # first time only
npm run dev              # opens http://localhost:3030
```

Edit `slides.md` (or files under `components/`, `pages/`, `snippets/`); the dev
server hot-reloads on save.

## Sanity-check the production build (optional)

```bash
npm run build -- --base /devcontainerctl/
npx serve dist           # preview the built bundle
```

## Publish

The GH Pages workflow deploys only on push to `master`.

```bash
git checkout -b slides/<topic> develop
# edit, commit
git push -u origin slides/<topic>
gh pr create --base develop          # merge to develop
gh pr create --base master --head develop  # promote to master → triggers deploy
```

Watch the run: GitHub → Actions → **Deploy slides**. Live URL appears in the
job summary, and at:

  https://<your-handle>.github.io/devcontainerctl/

## Manual redeploy

If you need to republish without a code change (e.g. after rotating Pages
config), trigger the workflow manually:

```bash
gh workflow run slides.yml --ref master
```

Or via the UI: Actions → **Deploy slides** → *Run workflow*.

## Troubleshooting

- **Build OK locally, broken on Pages**: confirm assets resolve under
  `/devcontainerctl/`. The `--base` flag is set in
  [`.github/workflows/slides.yml`](../.github/workflows/slides.yml); local
  `npm run dev` does not need it.
- **Deploy didn't run**: the workflow only triggers on `slides/**` or
  `.github/workflows/slides.yml` changes pushed to `master`. Use
  `gh workflow run` to force it.
- **404 on direct slide links**: keep Slidev's default hash router. GH Pages
  has no SPA rewrite, so `routerMode: history` would require a `404.html`
  fallback.
