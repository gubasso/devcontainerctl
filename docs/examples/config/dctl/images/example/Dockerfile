# Example user image for dctl. Copy this folder to ~/.config/dctl/images/example/
# and build it with `dctl image build example`, which tags it devimg/example:latest.
#
# dctl is agnostic. It builds the Dockerfile that you put in
# ~/.config/dctl/images/<name>/ and ships no image of its own. You own every
# tool in this image: install what your projects need to set up and run their
# own dev environments. Each project documents its own setup.
#
# A child image can start from this one with `FROM devimg/example:latest`.
# `dctl image build` builds a parent before its children.

FROM debian:stable-slim

# dctl passes the host user so the files in the workspace keep their owner.
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

RUN groupadd --gid "${USER_GID}" "${USERNAME}" \
  && useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/bash "${USERNAME}"

# -----------------------------------------------------------------------------
# Placeholder: the tools that every project needs, for example git and a shell
# that you like. This example installs nothing.
# -----------------------------------------------------------------------------
# RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
#   && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Placeholder: activation of a project environment when you enter its folder.
# Install one only if your projects use it, for example:
#   direnv               https://direnv.net
#   mise (mise activate) https://mise.jdx.dev
#   shadowenv            https://shopify.github.io/shadowenv/
#   autoenv              https://github.com/hyperupcall/autoenv
#   quickenv             https://codeberg.org/untitaker/quickenv
#   Environment Modules  https://envmodules.io
# dctl activates nothing. A command shell from `dctl ws run` or
# `dctl ws shell <cmd>` gets no project environment from dctl.
# -----------------------------------------------------------------------------
# RUN <install your activator>

# -----------------------------------------------------------------------------
# Placeholder: the managers that set up a project environment, for example:
#   Nix flakes, with nix-direnv   https://nix.dev  https://github.com/nix-community/nix-direnv
#   devenv                        https://devenv.sh
#   devbox                        https://www.jetify.com/devbox
#   flox                          https://flox.dev
#   mise                          https://mise.jdx.dev
#   asdf                          https://asdf-vm.com
#   pixi                          https://pixi.sh
#   aqua                          https://aquaproj.github.io
#   proto                         https://moonrepo.dev/proto
#   Hermit                        https://cashapp.github.io/hermit
#   pkgx                          https://pkgx.sh
# A project then runs a command in its environment with the native command of
# its manager, for example `direnv exec . CMD` or `nix develop --command CMD`.
# -----------------------------------------------------------------------------
# RUN <install your environment managers>

USER ${USERNAME}
