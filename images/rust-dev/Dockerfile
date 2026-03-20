# Rust development layer
# See: docs/ARCHITECTURE.md

# hadolint ignore=DL3007
FROM devimg/agents:latest
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Get USERNAME from parent image
ARG USERNAME
RUN test -n "$USERNAME" || { echo "USERNAME build arg is required"; exit 1; }
USER $USERNAME

# Rust dev tools (installed while stable toolchain is still available)
RUN cargo binstall --no-confirm --locked cargo-deny \
    && cargo binstall --no-confirm --locked taplo-cli \
    && cargo binstall --no-confirm --locked cargo-audit \
    && cargo binstall --no-confirm --locked typos-cli \
    && cargo binstall --no-confirm --locked cargo-nextest \
    && cargo binstall --no-confirm --locked ripsecrets

# Pre-commit tools installed via mise (non-cargo binaries)
RUN mise use --global gitleaks@latest \
    && mise reshim

# Remove default toolchain (project declares in rust-toolchain.toml)
RUN rustup default none \
    && rustup toolchain uninstall stable

WORKDIR /workspaces
