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
            # The shellharden hook keeps language: system: shellharden
            # publishes no pre-commit hook. pre-commit builds shellcheck,
            # shfmt, bashate, and commitizen from their upstream hooks.
            pkgs.shellharden

            # test runner; GNU parallel is what `bats --jobs` requires
            batsWithLibs
            pkgs.parallel

            # YAML/JSON tooling for the devcontainer manifests and schemas/
            pkgs.yq-go
            pkgs.jq

            # slides/ (Slidev) build, run by the slidev-build pre-push hook
            pkgs.nodejs

            # per-project git hooks, and prettier for the prettier hook, which
            # keeps language: system: prettier publishes no pre-commit hook.
            pkgs.pre-commit
            pkgs.prettier
          ];
          # stderr, not stdout: `nix develop --command CMD` runs this hook
          # first, and the two share stdout.
          shellHook = ''echo "dctl dev shell ready" >&2'';
        };
      }
    );
}
