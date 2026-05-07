---
theme: seriph
colorSchema: "all"
background: "linear-gradient(135deg, #0E2730 0%, #173F4F 55%, #2E6B2A 100%)"
title: dctl — Devcontainers without the boilerplate
info: |
  ## devcontainerctl
  Pre-built images and a unified CLI for AI-agent devcontainer sandboxes.
class: text-center
fonts:
  sans: "Source Sans Pro, Open Sans"
  serif: "Source Sans Pro"
  mono: "Fira Code"
  weights: "300,400,600,700"
  italic: true
  provider: google
drawings:
  persist: false
transition: slide-left
comark: true
duration: 15min
---

<div class="flex justify-center mb-4">
  <mdi-rocket-launch class="text-6xl text-brand-accent opacity-95" />
</div>

# dctl

<div class="text-2xl font-light tracking-wide opacity-95 mt-2">
Devcontainers without the boilerplate
</div>

<div class="text-sm opacity-60 mt-16 tracking-wider uppercase">
A <code>snackbar</code> story
</div>

<div class="text-base opacity-80 mt-2 font-light">
Docker &nbsp;→&nbsp; Dev Containers &nbsp;→&nbsp; <span class="text-brand-accent">dctl</span>
</div>

<!--
Frame the talk as a story about Ana, a backend dev whose container setup grows
from one project to many, and watch the boilerplate compound.
-->

---
layout: default
---

# Premises

If none of these sound like you, this project probably isn't for you.

- <mdi-shield-lock class="inline text-brand" /> &nbsp; **You care about security.** Containers don't fix everything, but the attack surface shrinks a lot when your tools don't run on your host.

- <mdi-arrow-split-vertical class="inline text-brand" /> &nbsp; **You want to multi-task.** Several containers and several agents against the same project — at the same time.

- <mdi-file-code-outline class="inline text-brand-warn" /> &nbsp; **You prefer declarative + composable + shareable** config over imperative scripts that drift.

- <mdi-robot-outline class="inline text-brand-deep" /> &nbsp; **You use AI agents** (Claude Code, Codex, Gemini) and want them isolated, with credentials forwarded automatically.

- <mdi-toolbox-outline class="inline text-brand-accent" /> &nbsp; **Your agents need your tooling.** Pre-commit hooks, language servers, formatters, build/test tools (mise, poetry, cargo) — that's how Claude Code and Codex CLI close their feedback loop. The container should mirror the host dev environment, not approximate it.

- <mdi-account-group-outline class="inline text-brand-warn" /> &nbsp; **You work on a team.** Onboarding should be one command, not a wiki page.

<!--
These are premises, not promises. If they hold, the rest of the talk shows how
much friction this project removes from a normal day.
-->

---
layout: center
class: text-center
background: 'linear-gradient(180deg, #173F4F 0%, #0E2730 100%)'
---

# Meet Ana

<div class="flex justify-center gap-12 mt-12 text-7xl">
  <mdi-account-tie-woman class="text-brand" />
  <mdi-arrow-right class="text-gray-400 self-center text-4xl" />
  <logos:python />
</div>

<div class="mt-12 text-xl opacity-80">
Backend developer. Starts a new Python API: <code>snackbar-api</code>.<br/>
Wants every tool inside a container. No host pollution.
</div>

<!--
Single project, single language, single developer. The simplest possible
starting point. Watch what she has to write.
-->

---
layout: center
class: text-center
background: 'linear-gradient(180deg, #173F4F 0%, #0E2730 100%)'
---

<div class="text-sm opacity-60 tracking-[0.5em] uppercase mb-3">Act 01</div>

# Pure Docker

<div class="flex justify-center gap-10 mt-10 text-7xl">
  <vscode-icons:file-type-docker />
</div>

<div class="mt-10 text-xl opacity-80">
One Dockerfile. One wrapper script.<br/>
Watch what Ana ends up owning.
</div>

<!--
Act I divider. The path Ana already started: hand-written Dockerfile,
hand-written run.sh, manual post-create steps.
-->

---
layout: two-cols
layoutClass: gap-12 act-docker
---

# One project, pure Docker

Ana needs two artifacts in her repo:

<div class="mt-8 space-y-6">

<div class="flex items-center gap-4">
  <vscode-icons:file-type-docker class="text-5xl" />
  <div>
    <div class="font-mono text-sm">Dockerfile</div>
    <div class="text-sm opacity-70">~45 lines: OS packages, gh CLI,<br/>non-root user, mise, pipx, npm agents</div>
  </div>
</div>

<div class="flex items-center gap-4">
  <vscode-icons:file-type-shell class="text-5xl" />
  <div>
    <div class="font-mono text-sm">run.sh</div>
    <div class="text-sm opacity-70">Wrapper around <code>docker run</code><br/>with mounts, env, tokens</div>
  </div>
</div>

<div class="flex items-center gap-4">
  <mdi-console class="text-5xl text-brand-warn" />
  <div>
    <div class="font-mono text-sm">docker exec ... pre-commit install</div>
    <div class="text-sm opacity-70">Manual post-create — every recreation</div>
  </div>
</div>

<div class="flex items-center gap-4">
  <mdi-console-line class="text-5xl text-brand" />
  <div>
    <div class="font-mono text-sm">docker exec -it snackbar-api-dev bash</div>
    <div class="text-sm opacity-70">Attach a shell — then run <code>claude</code>,<br/>tests, the dev server, …</div>
  </div>
</div>

</div>

::right::

<div class="mt-12">

<div class="text-sm opacity-70 mb-2">snackbar-api/run.sh</div>

```bash
docker run -d \
  --name snackbar-api-dev \
  --hostname snackbar-api-dev \
  --workdir /workspaces/snackbar-api \
  -v "$HOME/projects/snackbar-api:/workspaces/snackbar-api" \
  -v "$HOME/.gitconfig:/home/ana/.gitconfig:ro" \
  -v "$HOME/.config/gh:/home/ana/.config/gh" \
  -v "$HOME/.config/glab-cli:/home/ana/.config/glab-cli" \
  -v "$HOME/.claude:/home/ana/.claude" \
  -v "$HOME/.claude.json:/home/ana/.claude.json" \
  -v /tmp:/tmp \
  -e TERM="${TERM}" \
  -e COLORTERM="${COLORTERM:-truecolor}" \
  -e GH_TOKEN="$(gh auth token)" \
  -e GITLAB_TOKEN="$(glab auth status --show-token \
       2>/dev/null | sed -n 's/.*Token: //p' | head -n1)" \
  snackbar-api-dev:latest \
  bash -lc "sleep infinity"
```

</div>

<!--
Walk the audience through the highlights: container identity, workspace mount,
shared auth/agent mounts, terminal env, token extraction. One typo and the
container starts with broken state.
-->

---
layout: default
class: pain act-docker
---

# Pain already visible

- ~45 lines of Dockerfile written from scratch
- 15+ lines of `docker run` flags — kept in shell history or a wrapper script
- Token extraction (`$(gh auth token)`, the `glab` + `sed` pipeline) is manual
- `sleep infinity` is a keepalive hack she now owns
- No post-create hook — `pre-commit install` must be re-run after every recreation
- Any change to a mount = stop, remove, retype the whole command

<div class="mt-12 text-center text-2xl opacity-90">
And this is the <span class="underline decoration-brand-warn decoration-2 underline-offset-4">simplest possible case</span>: one project, one developer, one language.
</div>

<!--
This is the floor, not the ceiling. The next step is what happens when reality
shows up and she gets a second project.
-->

---
layout: center
class: text-center act-docker
background: 'linear-gradient(180deg, #173F4F 0%, #0E2730 100%)'
---

# A second project lands

<div class="flex justify-center items-center gap-10 mt-12 text-7xl">
  <logos:python />
  <mdi-plus class="text-3xl opacity-50 self-center" />
  <vscode-icons:file-type-rust />
</div>

<div class="mt-12 text-xl opacity-80">
<code>snackbar-api</code> (Python) is still going.<br/>
Now she also owns <code>order-engine</code> — a Rust service.
</div>

<div class="mt-10 text-lg opacity-70">
Same base setup. Different language toolchain. Different caches. Different post-create hooks.
</div>

<!--
Every team hits this moment. The question is what the second project costs.
-->

---
layout: two-cols
layoutClass: gap-8 act-docker
---

# Two projects, twice the boilerplate

<div class="mt-4 space-y-5">

<div class="border-l-4 border-brand proj-a pl-4 py-1">
  <div class="flex items-center gap-2 mb-2">
    <logos:python class="text-2xl" />
    <span class="font-mono text-base font-semibold">snackbar-api/</span>
  </div>
  <div class="flex items-center gap-3 ml-8">
    <vscode-icons:file-type-docker class="text-2xl" />
    <span class="font-mono text-xs">Dockerfile</span>
    <span class="text-xs opacity-60">— ~45 lines</span>
  </div>
  <div class="flex items-center gap-3 ml-8">
    <vscode-icons:file-type-shell class="text-2xl" />
    <span class="font-mono text-xs">run.sh</span>
    <span class="text-xs opacity-60">— ~15 lines</span>
  </div>
</div>

<div class="border-l-4 border-brand-deep proj-b pl-4 py-1">
  <div class="flex items-center gap-2 mb-2">
    <vscode-icons:file-type-rust class="text-2xl" />
    <span class="font-mono text-base font-semibold">order-engine/</span>
  </div>
  <div class="flex items-center gap-3 ml-8">
    <vscode-icons:file-type-docker class="text-2xl" />
    <span class="font-mono text-xs">Dockerfile</span>
    <span class="text-xs opacity-60">— ~45 lines, ~80% identical</span>
  </div>
  <div class="flex items-center gap-3 ml-8">
    <vscode-icons:file-type-shell class="text-2xl" />
    <span class="font-mono text-xs">run.sh</span>
    <span class="text-xs opacity-60">— same base mounts + Rust caches</span>
  </div>
</div>

</div>

::right::

<div class="mt-4 space-y-3">

<div class="text-sm opacity-70 mb-2">What's different in <code>order-engine/run.sh</code>:</div>

```bash
# Same 6 shared mounts as snackbar-api...
# Same TERM / COLORTERM / GH_TOKEN / GITLAB_TOKEN...

  -v "engine-rustup-ana:/home/ana/.rustup" \
  -v "engine-cargo-registry-ana:/home/ana/.cargo/registry" \
  -v "engine-cargo-git-ana:/home/ana/.cargo/git" \
  order-engine-dev:latest bash -lc "sleep infinity"
```

<div class="mt-4 text-sm opacity-70">And a different post-create:</div>

```bash
docker exec -it order-engine-dev \
  bash -lc "cargo build && pre-commit install"
```

</div>

<!--
Same shared mounts, repeated. Same env vars, repeated. Different cache volumes
and different post-create hooks per language. Nothing factors out.
-->

---
layout: default
class: act-docker
---

# What Docker can't share

- **4 manual files** for 2 projects — and growing linearly
- The shared base of the Dockerfile is **copy-pasted**, not shared
- The shared mounts in `run.sh` are **copy-pasted**, not shared
- Adding a tool to the base image = update **every** Dockerfile
- Adding a shared mount = update **every** `run.sh`
- Fixing a bug in the base = propagate to **every** repo, by hand
- The two files **will drift** over time

<div class="mt-12 text-center text-xl">
Docker has no answer for "shared base across projects." <br/>
<span class="opacity-60 text-base">Devcontainers help with config — but the duplication doesn't go away.</span>
</div>

<!--
Hand-off slide for the next section: the dev container CLI improves the runtime
config story (declarative JSON), but per-project duplication is unchanged.
That's where dctl comes in.
-->

---
layout: center
class: text-center
background: 'linear-gradient(180deg, #173F4F 0%, #0E2730 100%)'
---

<div class="text-sm opacity-60 tracking-[0.5em] uppercase mb-3">Act 02</div>

# Dev Containers

<div class="flex justify-center items-center gap-10 mt-12 text-7xl">
  <vscode-icons:file-type-docker />
  <mdi-plus class="text-4xl opacity-50 self-center" />
  <vscode-icons:file-type-json />
</div>

<div class="mt-12 text-xl opacity-80">
Same Ana. Same <code>snackbar-api</code>.<br/>
The runtime config moves out of shell history and into a declarative file.
</div>

<div class="mt-8 text-base opacity-60">
The Dockerfile doesn't change — devcontainers don't solve the image problem.
</div>

<!--
The dev container CLI consumes a JSON spec describing image, mounts, env, and
post-create hooks. Same image as before; the runtime is now declarative.
-->

---
layout: two-cols
layoutClass: gap-12 act-devc
---

# Python, dev container style

The Dockerfile from before is reused. New companion file:

<div class="mt-6 space-y-4">

<div class="flex items-center gap-4">
  <vscode-icons:file-type-docker class="text-4xl" />
  <div>
    <div class="font-mono text-sm">Dockerfile</div>
    <div class="text-sm opacity-70">~45 lines — <span class="text-brand-warn">unchanged</span></div>
  </div>
</div>

<div class="flex items-center gap-4">
  <vscode-icons:file-type-json class="text-4xl" />
  <div>
    <div class="font-mono text-sm">.devcontainer/devcontainer.json</div>
    <div class="text-sm opacity-70">~30 lines — image, mounts, env, hooks</div>
  </div>
</div>

<div class="flex items-center gap-4">
  <mdi-console-line class="text-4xl text-brand" />
  <div>
    <div class="font-mono text-sm">devcontainer up --workspace-folder .</div>
    <div class="text-sm opacity-70">No more 15-line <code>docker run</code></div>
  </div>
</div>

<div class="flex items-center gap-4">
  <mdi-console class="text-4xl text-brand-warn" />
  <div>
    <div class="font-mono text-sm">devcontainer exec --workspace-folder . bash</div>
    <div class="text-sm opacity-70">Attach a shell — then run <code>claude</code>, tests, the dev server, …</div>
  </div>
</div>

</div>

::right::

<div class="mt-4">

<div class="text-sm opacity-70 mb-2">snackbar-api/.devcontainer/devcontainer.json</div>

```json
{
  "name": "snackbar-api",
  "image": "snackbar-api-dev:latest",
  "remoteUser": "ana",
  "workspaceFolder": "/workspaces/snackbar-api",
  "containerEnv": {
    "TERM": "${localEnv:TERM}",
    "COLORTERM": "${localEnv:COLORTERM}"
  },
  "mounts": [
    "source=${localEnv:HOME}/.gitconfig,target=...,readonly",
    "source=${localEnv:HOME}/.config/gh,target=...",
    "source=${localEnv:HOME}/.claude,target=...",
    "source=/tmp,target=/tmp,type=bind"
  ],
  "remoteEnv": {
    "GH_TOKEN": "${localEnv:GH_TOKEN}",
    "GITLAB_TOKEN": "${localEnv:GITLAB_TOKEN}"
  },
  "postCreateCommand": { "pre-commit": "pre-commit install" }
}
```

</div>

<!--
Walk through the JSON: image reference, declared mounts, declared env vars,
and the postCreateCommand hook. The 15 docker run flags are now a file Ana
edits once and commits.
-->

---
layout: two-cols
layoutClass: gap-8 act-devc
---

# Two projects, two JSON files

<div class="mt-4 space-y-5">

<div class="border-l-4 border-brand proj-a pl-4 py-1">
  <div class="flex items-center gap-2 mb-2">
    <logos:python class="text-2xl" />
    <span class="font-mono text-base font-semibold">snackbar-api/</span>
  </div>
  <div class="flex items-center gap-3 ml-8">
    <vscode-icons:file-type-docker class="text-2xl" />
    <span class="font-mono text-xs">Dockerfile</span>
    <span class="text-xs opacity-60">— ~45 lines</span>
  </div>
  <div class="flex items-center gap-3 ml-8">
    <vscode-icons:file-type-json class="text-2xl" />
    <span class="font-mono text-xs">.devcontainer/devcontainer.json</span>
    <span class="text-xs opacity-60">— ~30 lines</span>
  </div>
</div>

<div class="border-l-4 border-brand-deep proj-b pl-4 py-1">
  <div class="flex items-center gap-2 mb-2">
    <vscode-icons:file-type-rust class="text-2xl" />
    <span class="font-mono text-base font-semibold">order-engine/</span>
  </div>
  <div class="flex items-center gap-3 ml-8">
    <vscode-icons:file-type-docker class="text-2xl" />
    <span class="font-mono text-xs">Dockerfile</span>
    <span class="text-xs opacity-60">— ~45 lines, ~80% identical</span>
  </div>
  <div class="flex items-center gap-3 ml-8">
    <vscode-icons:file-type-json class="text-2xl" />
    <span class="font-mono text-xs">.devcontainer/devcontainer.json</span>
    <span class="text-xs opacity-60">— ~30 lines, base block duplicated</span>
  </div>
</div>

</div>

::right::

<div class="mt-4">

<div class="text-sm opacity-70 mb-2">The shared base block — copy-pasted into both JSONs:</div>

```json
{
  "remoteUser": "ana",
  "containerEnv": {
    "TERM": "${localEnv:TERM}",
    "COLORTERM": "${localEnv:COLORTERM}"
  },
  "mounts": [
    "source=${localEnv:HOME}/.gitconfig,target=...,readonly",
    "source=${localEnv:HOME}/.config/gh,target=...",
    "source=${localEnv:HOME}/.claude,target=...",
    "source=/tmp,target=/tmp,type=bind"
  ],
  "remoteEnv": {
    "GH_TOKEN": "${localEnv:GH_TOKEN}",
    "GITLAB_TOKEN": "${localEnv:GITLAB_TOKEN}"
  }
}
```

<div class="mt-4 text-sm opacity-70">Rust adds <code>rustup</code> + <code>cargo</code> cache volumes and a <code>cargo build</code> hook. Python keeps its own <code>postCreateCommand</code>. Everything else? Identical, repeated.</div>

</div>

<!--
The devcontainer spec has no composition, no inheritance, no layering. Every
project is a standalone JSON file. Two projects = duplicated mounts and env.
-->

---
layout: default
class: act-devc
---

# What dev containers actually solve

- <mdi-file-document-outline class="inline text-brand" /> &nbsp; **Runtime config is declarative.** Mounts, env, hooks live in a file — not in shell history or a wrapper script.

- <mdi-hook class="inline text-brand" /> &nbsp; **`postCreateCommand` is a real hook.** No more manual <code>docker exec ... pre-commit install</code> after every recreate.

- <mdi-source-commit class="inline text-brand" /> &nbsp; **Config travels with the repo.** Teammates clone and get the same mounts, env, and setup commands.

- <mdi-application-cog-outline class="inline text-brand" /> &nbsp; **One command to start.** <code>devcontainer up</code> replaces the 15-line <code>docker run</code>.

- <mdi-heart-pulse class="inline text-brand" /> &nbsp; **Built-in keepalive.** The CLI injects its own shim (<code>overrideCommand: true</code> by default), so no <code>sleep infinity</code> in the Dockerfile or run args.

- <mdi-microsoft-visual-studio-code class="inline text-brand" /> &nbsp; **First-class editor support.** VS Code, JetBrains, and Codespaces all consume the spec — open the folder, the editor builds and attaches automatically. Language servers, debuggers, and extensions run **inside** the container.

<div class="mt-12 text-center text-lg opacity-80">
The spec is an industry standard. Anything that speaks <code>devcontainer.json</code> works.
</div>

<!--
This is the genuine win. Declarative runtime + standardized tooling. The
editor integration matters: language server, debugger, and extensions all
run inside the container, against the same toolchain the agent uses.
-->

---
layout: default
class: pain act-devc
---

# Pain that remains

- The Dockerfile is **still hand-written** — ~45 lines per project, no shared base.
- Now there are **two manual files** per project instead of one.
- The `devcontainer.json` schema has **no composition**: no inheritance, no layering, no reuse.
- The shared base block (mounts, env, `remoteUser`) is **copy-pasted** into every JSON.
- Add a tool to the image → update **every** Dockerfile.
- Add a shared mount → update **every** `devcontainer.json`.
- Token forwarding requires <code>${localEnv:GH_TOKEN}</code> in the JSON **and** the variable exported on the host (or a custom <code>initializeCommand</code>) — the spec has no built-in way to call <code>gh auth token</code>.

<div class="mt-12 text-center text-2xl opacity-90">
The runtime got declarative. The <span class="underline decoration-brand-warn decoration-2 underline-offset-4">duplication problem stayed</span>.
</div>

<!--
Devcontainers are a real improvement, but the shape of the duplication just
shifted from shell flags to JSON keys. That gap is what dctl fills next.
-->

---
layout: center
class: text-center
background: 'linear-gradient(135deg, #0E2730 0%, #173F4F 55%, #2E6B2A 100%)'
---

<div class="text-sm opacity-60 tracking-[0.5em] uppercase mb-3">Act 03</div>

# Enter `dctl`

<div class="mt-10 text-xl opacity-90">
One source of truth for Dockerfiles <span class="opacity-60">and</span> devcontainer config.<br/>
Composable, version-controllable, <span class="text-brand-accent">shared across projects and teammates</span>.
</div>

<div class="flex justify-center items-center gap-10 mt-12 text-7xl">
  <mdi-layers-outline class="text-brand" />
  <mdi-arrow-right class="text-gray-400 self-center text-4xl" />
  <mdi-rocket-launch class="text-brand-accent" />
</div>

<div class="mt-12 text-base opacity-70">
Same Ana. Same projects. Zero per-project boilerplate.
</div>

<!--
The pitch: dctl doesn't replace Docker or devcontainers — it builds on both.
The gain is conventions: managed images, layered config, and workspace-aware
container identity, all kept in one place users can edit and version.
-->

---
layout: default
class: act-dctl
---

# The principle — single source of truth

- <mdi-folder-cog-outline class="inline text-brand" /> &nbsp; **Dockerfiles and config live in one place** — under `~/.config/dctl/`, not scattered across repos.

- <mdi-layers-outline class="inline text-brand" /> &nbsp; **Devcontainer config is composed from named layers** — `base`, `agents`, `python`, `rust`, `dotfiles`. The final `devcontainer.json` is built piece by piece.

- <mdi-file-tree-outline class="inline text-brand" /> &nbsp; **A YAML manifest names the pieces in order** — change the manifest, change the composition. No copy-paste.

- <mdi-source-branch class="inline text-brand-accent" /> &nbsp; **Version-controlled and shareable** — your `~/.config/dctl/` is just files. Commit it to a personal dotfiles repo or share a team-wide baseline.

- <mdi-account-group-outline class="inline text-brand-warn" /> &nbsp; **Edit once, every project picks it up** — fix a mount in `base`, every workspace inherits the fix on the next `dctl init`.

<div class="mt-12 text-center text-lg opacity-80">
The duplication problem collapses because there is <span class="underline decoration-brand decoration-2 underline-offset-4">nothing left to duplicate</span>.
</div>

<!--
The conceptual core. Single-source-of-truth + composition is what unlocks
everything else: shared images, shared layers, project registry, work-clones.
-->

---
layout: two-cols
layoutClass: gap-10 act-dctl
---

# Shared Dockerfiles

One folder hosts every managed image. The directory name **is** the image name.

<div class="mt-6 space-y-4">

<div class="flex items-center gap-4">
  <mdi-folder-outline class="text-4xl text-brand" />
  <div>
    <div class="font-mono text-sm">~/.config/dctl/images/&lt;name&gt;/Dockerfile</div>
    <div class="text-sm opacity-70">One subdir per image — the dir name <em>is</em> the tag</div>
  </div>
</div>

<div class="flex items-center gap-4">
  <mdi-source-merge class="text-4xl text-brand" />
  <div>
    <div class="font-mono text-sm">FROM devimg/agents:latest</div>
    <div class="text-sm opacity-70">Language images compose on top of the shared base — native Docker, no magic</div>
  </div>
</div>

<div class="flex items-center gap-4">
  <mdi-console-line class="text-4xl text-brand-accent" />
  <div>
    <div class="font-mono text-sm">dctl image build --all</div>
    <div class="text-sm opacity-70">Builds the fleet in dependency order — no manual ordering</div>
  </div>
</div>

<div class="flex items-center gap-4">
  <mdi-pencil-outline class="text-4xl text-brand-warn" />
  <div>
    <div class="font-mono text-sm">$EDITOR ~/.config/dctl/images/python-dev/Dockerfile</div>
    <div class="text-sm opacity-70">Open and edit any time — it's your file</div>
  </div>
</div>

</div>

::right::

<div class="mt-8">

<div class="text-sm opacity-70 mb-2">Image hierarchy mirrors the config layering:</div>

```text
openSUSE Leap 16.0
        │
        ▼
devimg/agents:latest
  shared tools, AI agent CLIs,
  runtime managers, dev tooling
        │
        ├── devimg/python-dev:latest
        ├── devimg/rust-dev:latest
        └── devimg/zig-dev:latest
```

<div class="mt-6 text-sm opacity-70 mb-2">~/.config/dctl/images/</div>

```text
images/
├── agents/Dockerfile        # shared base
├── python-dev/Dockerfile    # FROM devimg/agents
├── rust-dev/Dockerfile      # FROM devimg/agents
└── zig-dev/Dockerfile       # FROM devimg/agents
```

</div>

<!--
Two layers of sharing: directory layout makes images discoverable by name,
and FROM lets language images inherit from the shared base. One tool added
to agents lights up every downstream image on the next build.
-->

---
layout: two-cols
layoutClass: gap-10 act-dctl
---

# Composable devcontainer config

The final `devcontainer.json` is **assembled** from named layers — not authored per project.

<div class="mt-6 space-y-4">

<div class="flex items-center gap-4">
  <mdi-folder-outline class="text-4xl text-brand" />
  <div>
    <div class="font-mono text-xs">~/.config/dctl/devcontainer/&lt;layer&gt;/devcontainer.json</div>
    <div class="text-sm opacity-70">Each layer is a partial config under its own dir</div>
  </div>
</div>

<div class="flex items-center gap-4">
  <vscode-icons:file-type-yaml class="text-4xl" />
  <div>
    <div class="font-mono text-sm">&lt;manifest&gt;.yaml</div>
    <div class="text-sm opacity-70">Lists the layers, in composition order</div>
  </div>
</div>

<div class="flex items-center gap-4">
  <mdi-source-merge class="text-4xl text-brand-accent" />
  <div>
    <div class="font-mono text-sm">dctl init</div>
    <div class="text-sm opacity-70">Merges the layers and caches the result</div>
  </div>
</div>

<div class="flex items-center gap-4">
  <mdi-database-outline class="text-4xl text-brand-warn" />
  <div>
    <div class="font-mono text-xs">~/.cache/dctl/devcontainer/&lt;name&gt;/devcontainer.json</div>
    <div class="text-sm opacity-70">Generated, schema-validated, never edited by hand</div>
  </div>
</div>

</div>

::right::

<div class="mt-4">

<div class="text-sm opacity-70 mb-2">python.yaml — the manifest</div>

```yaml
layers:
  - base # remoteUser, auth mounts, terminal env
  - agents # seccomp, agent CLI mounts
  - python # image tag, caches, hooks
```

<div class="mt-4 text-sm opacity-70 mb-2">~/.config/dctl/devcontainer/</div>

```text
devcontainer/
├── python.yaml          # manifest
├── rust.yaml            # manifest
├── base/
│   └── devcontainer.json
├── agents/
│   └── devcontainer.json
├── python/
│   └── devcontainer.json
└── rust/
    └── devcontainer.json
```

<div class="mt-3 text-xs opacity-60">
Layers merge in manifest order — later layers override earlier ones on conflict. Same shape as <code>FROM</code> in a Dockerfile, but for config.
</div>

</div>

<!--
The composition graph: many manifests, shared layers, one merged JSON per
project type. Edit base once, both python.yaml and rust.yaml pick it up.
The cache is the only thing devcontainer up actually reads.
-->

---
layout: default
class: act-dctl
---

# Per-project: just point at a manifest

<div class="grid grid-cols-2 gap-10 mt-6">

<div>

<div class="text-sm opacity-70 mb-2">~/.config/dctl/projects.yaml</div>

```yaml
projects:
  /home/ana/projects/snackbar-api:
    devcontainer-manifest: python
  /home/ana/projects/widget-api:
    devcontainer-manifest: python
  /home/ana/projects/order-engine:
    devcontainer-manifest: rust
```

<div class="mt-6 text-sm opacity-80">
Three projects. Two manifests. <strong>Zero per-project files.</strong>
</div>

</div>

<div>

<div class="space-y-4">

<div class="flex items-center gap-3">
  <mdi-numeric-1-circle-outline class="text-3xl text-brand" />
  <div>
    <div class="font-mono text-sm">dctl init</div>
    <div class="text-xs opacity-70">Pick a manifest, merge layers, register the project</div>
  </div>
</div>

<div class="flex items-center gap-3">
  <mdi-numeric-2-circle-outline class="text-3xl text-brand" />
  <div>
    <div class="font-mono text-sm">dctl ws up</div>
    <div class="text-xs opacity-70">Start the container from the merged cache</div>
  </div>
</div>

<div class="flex items-center gap-3">
  <mdi-numeric-3-circle-outline class="text-3xl text-brand-accent" />
  <div>
    <div class="font-mono text-sm">dctl ws shell claude</div>
    <div class="text-xs opacity-70">Drop in and start working</div>
  </div>
</div>

</div>

<div class="mt-8 text-xs opacity-60">
The merged config names the image (e.g. <code>devimg/python-dev:latest</code>). If it's not built locally, <code>dctl init</code> builds it for you.
</div>

</div>

</div>

<!--
The registry is the link between "this project on disk" and "this manifest".
Two Python projects share one manifest. Adding a third is one command.
-->

---
layout: two-cols
layoutClass: gap-10 act-dctl
---

# One command per task

The CLI maps 1-to-1 onto the workflow — no `--workspace-folder` ceremony, no `bash -lic`.

<div class="mt-6 space-y-3 text-sm">

<div class="flex items-baseline gap-3">
  <mdi-rocket-launch-outline class="text-xl text-brand self-center" />
  <code class="font-mono">dctl init --devcontainer python</code>
  <span class="opacity-70">— set up this project</span>
</div>

<div class="flex items-baseline gap-3">
  <mdi-play-circle-outline class="text-xl text-brand self-center" />
  <code class="font-mono">dctl ws up</code>
  <span class="opacity-70">— start the container</span>
</div>

<div class="flex items-baseline gap-3">
  <mdi-restart class="text-xl text-brand self-center" />
  <code class="font-mono">dctl ws reup</code>
  <span class="opacity-70">— recreate after a config change</span>
</div>

<div class="flex items-baseline gap-3">
  <mdi-console class="text-xl text-brand self-center" />
  <code class="font-mono">dctl ws shell</code>
  <span class="opacity-70">— drop into the container</span>
</div>

<div class="flex items-baseline gap-3">
  <mdi-robot-outline class="text-xl text-brand self-center" />
  <code class="font-mono">dctl ws run -- claude</code>
  <span class="opacity-70">— launch an agent inside</span>
</div>

<div class="flex items-baseline gap-3">
  <mdi-flash-outline class="text-xl text-brand self-center" />
  <code class="font-mono">dctl ws exec -- pytest -q</code>
  <span class="opacity-70">— run a one-shot command</span>
</div>

<div class="flex items-baseline gap-3">
  <mdi-stop-circle-outline class="text-xl text-brand-warn self-center" />
  <code class="font-mono">dctl ws down</code>
  <span class="opacity-70">— stop and clean up</span>
</div>

<div class="flex items-baseline gap-3">
  <mdi-hammer-wrench class="text-xl text-brand-accent self-center" />
  <code class="font-mono">dctl image build --all</code>
  <span class="opacity-70">— rebuild the image fleet, in order</span>
</div>

</div>

::right::

<div class="mt-4 text-xs">

<div class="opacity-70 mb-1"><strong>A.</strong> Shipped templates (sane defaults)</div>

```bash
make install && dctl deploy --all

cd ~/projects/snackbar-api
dctl init --devcontainer python && dctl ws up

cd ~/projects/order-engine
dctl init --devcontainer rust && dctl ws up
```

<div class="mt-3 opacity-70 mb-1"><strong>B.</strong> Shared/team config</div>

```bash
make install
git clone git@github.com:team/dctl-config ~/.config/dctl

cd ~/projects/snackbar-api
dctl init --devcontainer team-python && dctl ws up

cd ~/projects/order-engine
dctl init --devcontainer team-rust && dctl ws up
```

<div class="mt-3 opacity-80">
Same CLI. <code>dctl deploy</code> seeds the shipped defaults; <code>~/.config/dctl/</code> is just files — fork, symlink, or share it.
</div>

</div>

<!--
A: shipped templates path — make install + dctl deploy gives sane defaults.
B: shared config path — ~/.config/dctl/ is the team's repo, no deploy needed.
Same CLI in both; the difference is where the config comes from.
-->

---
layout: default
class: act-dctl
---

# What `dctl` quietly handles

- <mdi-key-variant class="inline text-brand" /> &nbsp; **Automatic credential forwarding.** `GH_TOKEN` and `GITLAB_TOKEN` extracted from `gh` / `glab` on every `exec`, `shell`, `run`. No `${localEnv:...}` boilerplate. Missing CLI? Silently skipped.

- <mdi-monitor-dashboard class="inline text-brand" /> &nbsp; **Terminal env forwarding.** `TERM`, `COLORTERM`, `TERM_PROGRAM`, Kitty vars — forwarded so colors and terminal-aware tools just work.

- <mdi-source-branch class="inline text-brand" /> &nbsp; **Work-clone awareness.** Sibling clones (`repo/`, `repo.42-add-auth/`) share config but get **separate containers**, keyed by workspace path. Linked-worktree git common dir is bind-mounted automatically.

- <mdi-shield-check-outline class="inline text-brand" /> &nbsp; **Schema-validated manifests.** YAML manifests are checked against `compose.schema.yaml` before merge — typos surface at `dctl init`, not at `devcontainer up`.

- <mdi-clock-outline class="inline text-brand-accent" /> &nbsp; **Weekly image refresh, opt-in.** A user-systemd timer runs `dctl image build --all` so the fleet stays current.

- <mdi-folder-multiple-outline class="inline text-brand-warn" /> &nbsp; **XDG-clean.** Seed ready-to-use templates in `~/.local/share/dctl/`, runtime config in `~/.config/dctl/`, generated cache in `~/.cache/dctl/`. Honors `XDG_*_HOME`. Nothing in the project repo.

<!--
The non-obvious wins. Each of these would be a custom shell snippet or wiki
page in the Docker/devcontainer flows. Here they're just defaults.
-->

---
layout: center
class: text-center
background: 'linear-gradient(135deg, #0E2730 0%, #173F4F 55%, #2E6B2A 100%)'
---

# The shape of the difference

<div class="grid grid-cols-3 gap-5 mt-10 text-left items-stretch">

<div class="recap-card recap-docker">
  <div class="recap-stage">01</div>
  <div class="flex items-center gap-3 mb-4">
    <vscode-icons:file-type-docker class="text-4xl" />
    <div class="text-lg font-semibold opacity-90">Docker</div>
  </div>
  <ul class="recap-list">
    <li>1 Dockerfile per project</li>
    <li>1–N wrapper scripts (<code>run</code>, <code>exec</code>, …)</li>
    <li>Manual post-create</li>
    <li>Drift across repos</li>
  </ul>
</div>

<div class="recap-card recap-devc">
  <div class="recap-stage">02</div>
  <div class="flex items-center gap-3 mb-4">
    <vscode-icons:file-type-json class="text-4xl" />
    <div class="text-lg font-semibold opacity-95">Dev Containers</div>
  </div>
  <ul class="recap-list">
    <li>1 Dockerfile + 1 JSON</li>
    <li>Declarative runtime</li>
    <li>Editor integration</li>
    <li class="opacity-60">Still no composition</li>
  </ul>
</div>

<div class="recap-card recap-dctl">
  <div class="recap-stage">03</div>
  <div class="flex items-center gap-3 mb-4">
    <mdi-rocket-launch class="text-4xl text-brand-accent" />
    <div class="text-xl font-bold text-brand-accent">dctl</div>
  </div>
  <ul class="recap-list recap-list-win">
    <li><strong>0 per-project files</strong></li>
    <li>Composable layers</li>
    <li>Shared images</li>
    <li>Auto credentials &amp; env</li>
  </ul>
</div>

</div>

<div class="mt-14">
  <div class="text-xl font-light opacity-80">
    Same Docker. Same devcontainer spec.
  </div>
  <div class="mt-2 text-3xl font-bold tracking-tight text-brand-accent">
    No more boilerplate.
  </div>
</div>

<!--
Recap slide. dctl doesn't replace either layer — it builds on both. The
value is in the conventions: managed images, layered config, workspace-aware
identity, and credential forwarding as a default.
-->
