# Rust development layer
# See: docs/ARCHITECTURE.md

# hadolint ignore=DL3007
FROM devimg/agents:latest
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Get USERNAME from parent image
ARG USERNAME
RUN test -n "$USERNAME" || { echo "USERNAME build arg is required"; exit 1; }
USER $USERNAME

# Rustup with no default toolchain (project declares in rust-toolchain.toml)
RUN rustup default none \
    && rustup toolchain uninstall stable

ENV PATH="/home/$USERNAME/.cargo/bin:$PATH"

WORKDIR /workspaces
