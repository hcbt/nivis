{
  description = "Shared Nix values for hcbt projects — superseded by devenv";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # NOT `follows`-ed onto this flake's nixpkgs, deliberately. devenv is Rust,
    # and the binaries on devenv.cachix.org are built against
    # `cachix/devenv-nixpkgs/rolling`. Overriding its nixpkgs changes the
    # derivation hash, every substituter misses, and `devenv-tasks` and its
    # crate graph compile from source on each machine and each CI run.
    devenv.url = "github:cachix/devenv";

    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
  };

  nixConfig = {
    extra-substituters = "https://devenv.cachix.org";
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
  };

  outputs =
    inputs@{
      nixpkgs,
      devenv,
      git-hooks,
      ...
    }:
    let
      nivisLib = import ./lib { inherit (nixpkgs) lib; };

      forEachSystem = nixpkgs.lib.genAttrs nivisLib.defaultSystems;

      flakePkgsFor = forEachSystem (system: nixpkgs.legacyPackages.${system});

      devenvPkgsFor = forEachSystem (system: import devenv.inputs.nixpkgs { inherit system; });
    in
    {
      lib = nivisLib;

      checks = forEachSystem (system: {
        # `mkCleanSrc` is the one function with behaviour worth asserting: it
        # decides what a consumer's checks copy into the store, and a filter
        # that silently stops excluding is invisible until a build's hash starts
        # moving with somebody's local `.direnv`.
        lib-clean-src =
          let
            filtered = nivisLib.mkCleanSrc {
              src = ./.;
              excludes = [ "/lib" ];
            };
          in
          nixpkgs.legacyPackages.${system}.runCommand "lib-clean-src" { } ''
            test -e ${filtered}/flake.nix || { echo "mkCleanSrc dropped a file it should keep" >&2; exit 1; }
            test ! -e ${filtered}/lib || { echo "mkCleanSrc kept a path it was told to exclude" >&2; exit 1; }
            touch $out
          '';

        pre-commit = git-hooks.lib.${system}.run {
          src = ./.;
          package = devenvPkgsFor.${system}.prek;
          inherit ((import ./devenv.nix { pkgs = devenvPkgsFor.${system}; }).git-hooks)
            hooks
            excludes
            ;
        };
      });

      devShells = forEachSystem (system: {
        default = devenv.lib.mkShell {
          inherit inputs;
          pkgs = devenvPkgsFor.${system};
          modules = [
            (import ./devenv.nix {
              pkgs = devenvPkgsFor.${system};
              # Same set as `pkgs` here. The split only matters in
              # `checks.pre-commit`, which builds from this flake's nixpkgs and
              # borrows only the tools.
              toolPkgs = flakePkgsFor.${system};
            })
          ];
        };
      });
    };
}
