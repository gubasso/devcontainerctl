{
  description = "devcontainerctl (dctl) dev shell — bash CLI + bats tests";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # The store guard of the canon (exobrain): `exobrain store-guard --daily`
    # in .envrc warns about working-tree copies in the Nix store.
    exobrain-tech = {
      url = "github:gubasso/exobrain-tech/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    # `...` is required: Nix always applies `outputs (inputs // { self = …; })`,
    # so a closed attrset breaks the flake the moment `self` is unused.
    {
      nixpkgs,
      flake-utils,
      exobrain-tech,
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

        # pre-commit, the test runners, the tools that the Makefile targets
        # and the `language: system` hooks call, and the node of the slides
        # build. pre-commit builds every other hook tool from its upstream
        # hook. Without this shell, `make check` and `make test` cannot run
        # inside a dctl agents container: these tools are not in the
        # container's global toolset, and by design they should not be
        # (see nix-secrets images/agents/flake.nix, SCOPE).
        devShells.default = pkgs.mkShell {
          packages = [
            # The shellharden hook keeps language: system: shellharden
            # publishes no pre-commit hook. pre-commit builds shellcheck,
            # shfmt, bashate, and commitizen from their upstream hooks.
            pkgs.shellharden

            # test runner; GNU parallel is what `bats --jobs` requires
            batsWithLibs
            pkgs.parallel
            # script, which gives the picker test of tests/dctl_test.bats a
            # terminal. It is not a base tool of the host.
            pkgs.util-linux

            # YAML/JSON tooling for the devcontainer manifests and schemas/
            pkgs.yq-go
            pkgs.jq

            # slides/ (Slidev) build, run by the slidev-build pre-push hook
            pkgs.nodejs

            # per-project git hooks, and prettier for the prettier hook, which
            # keeps language: system: prettier publishes no pre-commit hook.
            pkgs.pre-commit
            pkgs.prettier
          ]
          # exobrain, the store guard that .envrc runs once a day. exobrain-tech
          # builds it for x86_64-linux alone, so the other systems keep their shell.
          ++ pkgs.lib.optionals (system == "x86_64-linux") [
            exobrain-tech.packages.${system}.default
          ];
          # stderr, not stdout: `nix develop --command CMD` runs this hook
          # first, and the two share stdout.
          shellHook = ''echo "dctl dev shell ready" >&2'';
        };
      }
    );
}
