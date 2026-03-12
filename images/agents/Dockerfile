# Base layer for AI agent sandboxing
# See: docs/ARCHITECTURE.md
#
# Supply chain note: Bun, Claude Code, OpenCode, and the mise
# refresh are installed via curl-pipe. Codex is installed via Bun (npm-style).
# gh is installed via the official GitHub APT repo. Node.js LTS, neovim,
# Python, fzf, pre-commit, and glab are installed via mise. eza, mise, zoxide,
# starship, and bottom are installed via cargo-binstall (prebuilt binaries).
# trash-cli via pipx. Rust toolchain via rustup. Lazy plugins, treesitter
# parsers, and Mason tools are pre-installed at build time. For stronger
# guarantees, pin versions and validate checksums. Current approach favors
# simplicity for personal devcontainers with weekly rebuilds.

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# System dependencies + build tools for native extensions
# Package names follow Debian conventions. Verify availability with:
#   docker run --rm debian:bookworm-slim bash -c "apt-get update && apt-cache policy <pkg>"
# Or check: https://packages.debian.org/bookworm/
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    unzip \
    ripgrep \
    fd-find \
    bat \
    bats \
    fish \
    jq \
    tree \
    htop \
    sudo \
    openssh-client \
    rsync \
    stow \
    # Kitty terminal: terminfo for xterm-kitty (enables keyboard protocol inside containers)
    kitty-terminfo \
    # Build dependencies (for Python wheels, Rust crates, etc.)
    build-essential \
    libffi-dev \
    libssl-dev \
    pkg-config \
    libclang-dev \
    # X11 build dependencies (suckless: dwm, st, dmenu, etc.)
    libx11-dev \
    libxft-dev \
    libxinerama-dev \
    # Neovim optional deps (checkhealth providers, :help lazy-pkg-spec)
    mercurial \
    golang-go \
    ruby-full \
    php-cli \
    composer \
    default-jdk \
    lua5.4 \
    luarocks \
    cpanminus \
    && rm -rf /var/lib/apt/lists/* \
    # Create fd symlink (Debian names binary fdfind to avoid conflict)
    && if [ -x /usr/bin/fdfind ]; then ln -sf /usr/bin/fdfind /usr/local/bin/fd; fi \
    && if [ -x /usr/bin/batcat ]; then ln -sf /usr/bin/batcat /usr/local/bin/bat; fi \
    && if [ -x /usr/bin/lua5.4 ] && [ ! -x /usr/local/bin/lua ]; then ln -sf /usr/bin/lua5.4 /usr/local/bin/lua; fi

# Non-root user with passwordless sudo
# USERNAME must match host $USER for config file consistency
ARG USERNAME
ARG USER_UID=1000
ARG USER_GID=1000

RUN test -n "$USERNAME" || { echo "USERNAME build arg is required"; exit 1; } \
    && groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m -s /bin/bash $USERNAME \
    && rm -f /home/$USERNAME/.bashrc /home/$USERNAME/.bash_logout /home/$USERNAME/.profile \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# Pre-create directories for mounts
RUN install -d -m 0700 -o $USERNAME -g $USERNAME /home/$USERNAME/.ssh

# fzf-tab-completion: bash Tab completion via fzf (no Debian package available)
# Checked first by bash/.config/bash/rc.d/10-fzf.bash
RUN git clone --depth=1 https://github.com/lincheney/fzf-tab-completion /usr/share/fzf-tab-completion \
    && rm -rf /usr/share/fzf-tab-completion/.git \
    && test -r /usr/share/fzf-tab-completion/bash/fzf-bash-completion.sh

# GitHub CLI (gh): official APT repo tracks latest releases for Debian
RUN mkdir -p -m 755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

USER $USERNAME
WORKDIR /home/$USERNAME

# Install Bun
RUN curl -fsSL https://bun.com/install | bash

ENV BUN_INSTALL="/home/$USERNAME/.bun"

# Rust toolchain (for cargo-binstall chain)
# Minimal profile: just rustc + cargo + rust-std (no docs/clippy/rustfmt)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --default-toolchain stable --profile minimal

ENV PATH="/home/$USERNAME/.local/share/mise/shims:/home/$USERNAME/.cargo/bin:$BUN_INSTALL/bin:/home/$USERNAME/.local/bin:$PATH"

# Default editor (neovim installed below via mise)
ENV EDITOR=nvim
ENV VISUAL=nvim

# CLI tools via cargo (prebuilt where available, source where needed)
# tree-sitter-cli: compiled from source — needs libclang-dev (bindgen); prebuilt needs GLIBC_2.39 (bookworm has 2.36)
# Preference: apt > cargo-binstall > cargo-install
RUN cargo install cargo-binstall --locked \
    && { cargo binstall --no-confirm mise || cargo install --locked mise; } \
    && { cargo binstall --no-confirm zoxide || cargo install --locked zoxide; } \
    && { cargo binstall --no-confirm eza || cargo install --locked eza; } \
    && { cargo binstall --no-confirm starship || cargo install --locked starship; } \
    && { cargo binstall --no-confirm ast-grep || cargo install --locked ast-grep; } \
    && { cargo binstall --no-confirm shellharden || cargo install --locked shellharden; } \
    && cargo install --locked tree-sitter-cli

# Node.js LTS via mise (needed for bun-installed packages with #!/usr/bin/env node shebangs)
RUN mise use --global node@lts \
    && mise reshim

# Neovim (latest stable) + Python + pre-commit + Go via mise
# Intentionally unpinned: @latest with default backends matches the weekly-rebuild
# rolling model. If a backend drifts, the build breaks loud — fix forward.
# Refresh mise binary: cached cargo-binstall version may have registry/parser bugs
# hadolint ignore=DL3013
RUN curl -fsSL https://mise.run | MISE_INSTALL_PATH="$HOME/.cargo/bin/mise" sh \
    && mise use --global neovim@latest \
    && mise use --global python@latest \
    && mise use --global pre-commit@latest \
    && mise use --global go@latest \
    && mise use --global fzf@latest \
    && mise use --global gitlab:gitlab-org/cli@latest \
    && pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir pipx \
    && python -m pipx install trash-cli \
    && mise reshim

# Neovim provider hosts (node, ruby, python)
# hadolint ignore=DL3013,DL3028
RUN bun add -g neovim \
    && gem install --no-document --user-install --bindir "${HOME}/.local/bin" neovim \
    && pipx install pynvim

# Build-time nvim bootstrap: install Lazy plugins + treesitter parsers + Mason tools
# Uses host nvim config via XDG_CONFIG_HOME; headless deterministic exit via os.exit(0)
# hadolint ignore=DL3022
COPY --from=dotfiles --chown=$USERNAME:$USERNAME /nvim/.config/nvim /tmp/nvim-bootstrap/.config/nvim
RUN mkdir -p /tmp/nvim-bootstrap/.config/kitty \
    && set -euo pipefail \
    && printf '%s\n' '#!/bin/bash' \
         'exec env XDG_CONFIG_HOME=/tmp/nvim-bootstrap/.config nvim --headless --cmd "set nomore" --cmd "set cmdheight=1" --cmd "set shortmess+=IF" "$@"' \
         > /tmp/nvim_boot \
    && chmod +x /tmp/nvim_boot \
    && /tmp/nvim_boot "+Lazy! restore" "+lua os.exit(0)" \
    && /tmp/nvim_boot \
         "+Lazy! load nvim-treesitter" \
         "+TSUpdateSync" \
         "+lua os.exit(0)" 2>&1 | tee /tmp/ts.log \
    && if grep -Eqi "(failed|error:)" /tmp/ts.log; then \
         echo "ERROR: Treesitter installation reported failures:"; \
         grep -Ein "(failed|error:)" /tmp/ts.log | head -50; \
         exit 1; \
       fi \
    # Preflight: detect duplicate ensure_installed entries (causes hangs/errors)
    && for f in \
         /tmp/nvim-bootstrap/.config/nvim/lua/plugins/mason-tool-installer.lua \
         /tmp/nvim-bootstrap/.config/nvim/lua/plugins/mason-lspconfig.lua \
         /tmp/nvim-bootstrap/.config/nvim/lua/plugins/treesitter.lua; do \
         dupes=$(sed -n '/ensure_installed\s*=\s*{/,/}/p' "$f" \
           | awk -F'"' '{for(i=2;i<=NF;i+=2) if($i!="") print $i}' | sort | uniq -d); \
         if [ -n "$dupes" ]; then \
           echo "ERROR: Duplicate ensure_installed entries in $(basename "$f"):"; \
           echo "$dupes"; \
           exit 1; \
         fi; \
       done \
    # Mason tools: headless synchronous install with timeout
    && echo "[nvim-bootstrap] Mason install start" \
    && mason_rc=0 \
    && timeout 300 /tmp/nvim_boot \
         "+Lazy! load mason-tool-installer.nvim" \
         "+MasonToolsInstallSync" \
         "+lua os.exit(0)" 2>&1 | tee /tmp/mason.log \
       || mason_rc=$? \
    && if [ "$mason_rc" -eq 124 ]; then \
         echo "ERROR: Mason install timed out (5min) — likely a hang. Check for duplicate ensure_installed entries or network issues."; \
         tail -30 /tmp/mason.log; \
         exit 1; \
       elif [ "$mason_rc" -ne 0 ]; then \
         echo "ERROR: Mason install failed (exit $mason_rc):"; \
         tail -30 /tmp/mason.log; \
         exit 1; \
       fi \
    && if grep -Eqi "(failed|error:)" /tmp/mason.log; then \
         echo "ERROR: Mason tool installation reported failures:"; \
         grep -Ein "(failed|error:)" /tmp/mason.log | head -50; \
         exit 1; \
       fi \
    && echo "[nvim-bootstrap] Mason install complete" \
    && rm -f /tmp/ts.log /tmp/mason.log \
    && rm -f /tmp/nvim_boot && rm -rf /tmp/nvim-bootstrap

# AI Agent CLIs (rolling: rebuild weekly, or on-demand via --refresh-agents)
# Cache-bust: dctl image build --refresh-agents agents
ARG CACHEBUST_AGENTS=0
# Claude Code (native installer - auto-updates)
RUN echo "agent-cache-bust=$CACHEBUST_AGENTS" \
    && curl -fsSL https://claude.ai/install.sh | bash
# Codex CLI (OpenAI) via Bun | OpenCode via Bun | Gemini CLI via npm
RUN bun add -g @openai/codex opencode-ai && npm install -g @google/gemini-cli@latest

WORKDIR /workspaces

# Shared devcontainer defaults inherited by child images and merged with project-local devcontainer.json
LABEL devcontainer.metadata='[ \
  { \
    "remoteUser": "${localEnv:USER}", \
    "updateRemoteUserUID": false, \
    "init": true, \
    "shutdownAction": "none", \
    "containerEnv": { "TERM": "${localEnv:TERM}", "COLORTERM": "truecolor" }, \
    "mounts": [ \
      { \
        "source": "${localEnv:HOME}/.gitconfig", \
        "target": "${localEnv:HOME}/.gitconfig", \
        "type": "bind", \
        "readonly": true \
      }, \
      { \
        "source": "${localEnv:DOTFILES}", \
        "target": "${localEnv:DOTFILES}", \
        "type": "bind" \
      }, \
      { \
        "source": "${localEnv:DOTFILES}/claude/.claude", \
        "target": "${localEnv:HOME}/.claude", \
        "type": "bind" \
      }, \
      { \
        "source": "${localEnv:HOME}/.claude.json", \
        "target": "${localEnv:HOME}/.claude.json", \
        "type": "bind" \
      }, \
      { \
        "source": "${localEnv:DOTFILES}/claude/.local/bin/claude-session", \
        "target": "${localEnv:HOME}/.local/bin/claude-session", \
        "type": "bind" \
      }, \
      { \
        "source": "${localEnv:HOME}/.config/gcloud", \
        "target": "${localEnv:HOME}/.config/gcloud", \
        "type": "bind", \
        "readonly": true \
      }, \
      { \
        "source": "${localEnv:DOTFILES}/codex/.codex", \
        "target": "${localEnv:HOME}/.codex", \
        "type": "bind" \
      }, \
      { \
        "source": "${localEnv:HOME}/.local/share/opencode", \
        "target": "${localEnv:HOME}/.local/share/opencode", \
        "type": "bind" \
      }, \
      { \
        "source": "${localEnv:DOTFILES}/opencode/.config/opencode", \
        "target": "${localEnv:HOME}/.config/opencode", \
        "type": "bind" \
      }, \
      { \
        "source": "${localEnv:DOTFILES}/gemini/.gemini", \
        "target": "${localEnv:HOME}/.gemini", \
        "type": "bind" \
      }, \
      { \
        "source": "${localEnv:DOTFILES}/nvim/.config/nvim", \
        "target": "${localEnv:HOME}/.config/nvim", \
        "type": "bind" \
      }, \
      { \
        "source": "${localEnv:HOME}/.config/gh", \
        "target": "${localEnv:HOME}/.config/gh", \
        "type": "bind" \
      }, \
      { \
        "source": "${localEnv:HOME}/.config/glab-cli", \
        "target": "${localEnv:HOME}/.config/glab-cli", \
        "type": "bind" \
      } \
    ], \
    "postCreateCommand": { \
      "dotfiles": "${localEnv:DOTFILES}/.devcontainer/setup-dotfiles ${localEnv:DOTFILES}" \
    } \
  } \
]'

CMD ["sleep", "infinity"]
