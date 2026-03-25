# Base layer for AI agent sandboxing
# See: docs/ARCHITECTURE.md
#
# Supply chain note: Bun, Claude Code, OpenCode, and the mise
# refresh are installed via curl-pipe. Codex is installed via Bun (npm-style).
# gh is installed via the official GitHub APT repo. Node.js LTS, Neovim,
# Python, fzf, pre-commit, glab, bats, and yq are installed via mise. eza, mise, zoxide,
# and starship are installed via cargo-binstall.
# trash-cli via pipx. Rust toolchain via rustup. Neovim runs a minimal
# config in containers (no plugins, LSP, or treesitter). For stronger
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
    && rm -rf /var/lib/apt/lists/* \
    # Create fd symlink (Debian names binary fdfind to avoid conflict)
    && if [ -x /usr/bin/fdfind ]; then ln -sf /usr/bin/fdfind /usr/local/bin/fd; fi \
    && if [ -x /usr/bin/batcat ]; then ln -sf /usr/bin/batcat /usr/local/bin/bat; fi

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
# Preference: cargo-binstall > cargo-install
RUN cargo install cargo-binstall --locked \
    && cargo binstall --no-confirm --locked mise \
    && cargo binstall --no-confirm --locked zoxide \
    && cargo binstall --no-confirm --locked eza \
    && cargo binstall --no-confirm --locked starship \
    && cargo binstall --no-confirm --locked ast-grep \
    && cargo binstall --no-confirm --locked shellharden

# Node.js LTS via mise (needed for bun-installed packages with #!/usr/bin/env node shebangs)
RUN --mount=type=secret,id=gh_token,mode=0444 \
    export GITHUB_TOKEN="$(cat /run/secrets/gh_token 2>/dev/null || true)" \
    && mise use --global node@lts \
    && mise reshim

# Neovim (latest stable) + Python + pre-commit + fzf + glab via mise
# Intentionally unpinned: @latest with default backends matches the weekly-rebuild
# rolling model. If a backend drifts, the build breaks loud — fix forward.
# Refresh mise binary: cached cargo-binstall version may have registry/parser bugs
# hadolint ignore=DL3013
RUN --mount=type=secret,id=gh_token,mode=0444 \
    export GITHUB_TOKEN="$(cat /run/secrets/gh_token 2>/dev/null || true)" \
    && curl -fsSL https://mise.run | MISE_INSTALL_PATH="$HOME/.cargo/bin/mise" sh \
    && mise use --global neovim@latest \
    # Force standard (non-freethreaded) Python: 3.14+ defaults to freethreaded builds
    # (no GIL), whose stripped precompiled binaries lack the lib/ dir mise expects.
    # Standard build keeps full compatibility with C extensions and conventional layout.
    && MISE_PYTHON_PRECOMPILED_FLAVOR=install_only_stripped mise use --global python@latest \
    && mise use --global pre-commit@latest \
    && mise use --global fzf@latest \
    && mise use --global gitlab:gitlab-org/cli@latest \
    && mise use --global bats@latest \
    && mise use --global yq@latest \
    && pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir pipx \
    && python -m pipx install trash-cli \
    && mise reshim

# AI Agent CLIs (rolling: rebuild weekly, or on-demand via --refresh-agents)
# Cache-bust: dctl image build --refresh-agents agents
ARG CACHEBUST_AGENTS=0
# Claude Code (native installer - auto-updates)
RUN echo "agent-cache-bust=$CACHEBUST_AGENTS" \
    && curl -fsSL https://claude.ai/install.sh | bash
# Codex CLI (OpenAI) via Bun | OpenCode via Bun | Gemini CLI via npm
RUN bun add -g @openai/codex opencode-ai && npm install -g @google/gemini-cli@latest

# Kitty remote control client (standalone static binary, no runtime deps)
# Enables tab-title hooks and notifications from inside containers via kitty's Unix socket
RUN curl -fsSL -o /tmp/kitten \
    https://github.com/kovidgoyal/kitty/releases/latest/download/kitten-linux-amd64 \
    && install -m 0755 /tmp/kitten /home/$USERNAME/.local/bin/kitten \
    && rm -f /tmp/kitten

WORKDIR /workspaces

CMD ["sleep", "infinity"]
