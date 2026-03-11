# Python development layer
# See: docs/ARCHITECTURE.md

# hadolint ignore=DL3007
FROM devimg/agents:latest
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Get USERNAME from parent image
ARG USERNAME
RUN test -n "$USERNAME" || { echo "USERNAME build arg is required"; exit 1; }
USER $USERNAME

# System deps for native Python extensions (M2Crypto needs swig + OpenSSL headers)
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    swig \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*
USER $USERNAME

# Poetry + yq (provides tomlq for pyproject parsing) via mise pipx backend
RUN mise use --global pipx:poetry@latest \
    && mise use --global pipx:yq@latest \
    && mise reshim

# Poetry config: virtualenvs inside project directories
RUN poetry config virtualenvs.in-project true

WORKDIR /workspaces
