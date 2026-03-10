# Zig development layer
# See: docs/ARCHITECTURE.md

# hadolint ignore=DL3007
FROM devimg/agents:latest
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Get USERNAME from parent image
ARG USERNAME
RUN test -n "$USERNAME" || { echo "USERNAME build arg is required"; exit 1; }
USER $USERNAME

# System deps: minisign (zig-zls-init signature verification),
# xz-utils (tar -xJ for zls archives)
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    minisign \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*
USER $USERNAME

# anyzig: multi-version zig launcher (reads version from build.zig.zon)
ARG ANYZIG_VERSION=v2025_10_15
RUN set -euo pipefail \
    && arch="$(uname -m)" \
    && case "$arch" in \
         x86_64) anyzig_arch="x86_64" ;; \
         aarch64) anyzig_arch="aarch64" ;; \
         *) echo "ERROR: unsupported architecture '$arch' for anyzig"; exit 1 ;; \
       esac \
    && curl -fsSL "https://github.com/marler8997/anyzig/releases/download/${ANYZIG_VERSION}/anyzig-${anyzig_arch}-linux.tar.gz" \
       | tar xz -C "/home/$USERNAME/.local/bin/" \
    && test -x "/home/$USERNAME/.local/bin/zig"

# zig-zls-init: per-project zls download + .nvim.lua scaffold
# hadolint ignore=DL3022
COPY --from=dotfiles --chown=$USERNAME:$USERNAME /bin/.local/bin/zig-zls-init /home/$USERNAME/.local/bin/zig-zls-init
RUN chmod +x /home/$USERNAME/.local/bin/zig-zls-init

# Predictable cache path for volume mounts
ENV ZIG_GLOBAL_CACHE_DIR="/home/$USERNAME/.cache/zig"

WORKDIR /workspace
