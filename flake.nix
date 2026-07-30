{
  description = "devcontainerctl (dctl) dev shell — bash CLI + bats tests";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    # `...` is required: Nix always applies `outputs (inputs // { self = …; })`,
    # so a closed attrset breaks the flake the moment `self` is unused.
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        # bats plus the bats-support / bats-assert helper libraries. tests/
        # currently rolls its own assertions in test_helper.bash and loads
        # neither, but the sibling runtime branch's suite does.
        batsWithLibs = pkgs.bats.withLibraries (p: [
          p.bats-support
          p.bats-assert
        ]);
      in
      {
        formatter = pkgs.nixfmt-rfc-style;

        # Everything `make check` and `make test` shell out to. Without this
        # shell, neither target can run inside a dctl agents container: the tools
        # are not in the container's global toolset, and by design they should not
        # be — per-project hook tools and test runners belong to the project's own
        # devShell (see nix-secrets images/agents/flake.nix, SCOPE).
        devShells.default = pkgs.mkShell {
          packages = [
            # bash lint/format — mirrors the pre-commit hookset (CLAUDE.md)
            pkgs.shellcheck
            pkgs.shfmt
            pkgs.shellharden
            pkgs.bashate

            # test runner; GNU parallel is what `bats --jobs` requires
            batsWithLibs
            pkgs.parallel

            # YAML/JSON tooling for the devcontainer manifests and schemas/
            pkgs.yq-go
            pkgs.jq

            # per-project git hooks
            pkgs.pre-commit
          ];
          shellHook = ''echo "dctl dev shell ready"'';
        };
      }
    );
}
