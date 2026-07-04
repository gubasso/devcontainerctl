{
  description = "devcontainerctl (dctl) dev shell — bash CLI + bats tests";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        # bats plus the bats-support / bats-assert helper libraries used by tests/test_helper.bash
        batsWithLibs = pkgs.bats.withLibraries (p: [
          p.bats-support
          p.bats-assert
        ]);
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            # bash lint/format — mirrors the pre-commit hookset (CLAUDE.md)
            pkgs.shellcheck
            pkgs.shfmt
            pkgs.shellharden
            pkgs.bashate

            # test runner + helper libraries (bats-support / bats-assert)
            batsWithLibs
            # GNU parallel — bats requires it to run tests with --jobs
            pkgs.parallel

            # YAML/JSON tooling for devcontainer manifests + schemas/
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
