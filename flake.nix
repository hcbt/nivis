{
  description = "Shared flake-parts scaffolding for hcbt projects";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Consumed only by `flakeModules.bun`. Pinned by revision — this one is tag
    # 2.1.2 — because `bun.nix`'s schema has no stability guarantee between
    # bun2nix versions, so the generator moving under a repo is what makes its
    # committed expression fail to evaluate.
    #
    # `follows` is load-bearing rather than tidiness: the hook runs `pkgs.bun`
    # from THIS nixpkgs inside the sandbox, and a consumer's dev shell runs
    # `pkgs.bun` from the nixpkgs it follows nivis onto. Left unfollowed they
    # are two different bun versions installing the same lockfile.
    bun2nix.url = "github:nix-community/bun2nix/0f2a1f0b6f42cebe3b149bf62d38754c5e0e9729";
    bun2nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      git-hooks,
      treefmt-nix,
      bun2nix,
      ...
    }:
    let
      nivisLib = import ./lib { inherit (nixpkgs) lib; };

      # Each module is partially applied with nivis' OWN inputs here, before a
      # consumer ever sees it. flake-parts threads the CONSUMING flake's
      # `inputs` into every module it evaluates, so a module that reached for
      # `inputs.git-hooks` would force every consumer to declare git-hooks and
      # treefmt-nix itself — which is most of the boilerplate this exists to
      # remove. Closing over them here is what reduces a consumer to one input.
      flakeModules = {
        default = import ./modules {
          inherit nivisLib;
          gitHooks = git-hooks;
          treefmtNix = treefmt-nix;
        };
        lib = import ./modules/lib.nix { inherit nivisLib; };
        git-hooks = import ./modules/git-hooks.nix {
          inherit nivisLib;
          gitHooks = git-hooks;
          treefmtNix = treefmt-nix;
        };
        treefmt = import ./modules/treefmt.nix {
          inherit nivisLib;
          treefmtNix = treefmt-nix;
        };
        repo = import ./modules/repo.nix {
          inherit nivisLib;
          treefmtNix = treefmt-nix;
        };

        # Language-specific, so deliberately absent from `default`: a bun
        # project imports this alongside it.
        bun = import ./modules/bun.nix { inherit bun2nix; };
        shell = import ./modules/shell.nix {
          inherit nivisLib;
          gitHooks = git-hooks;
          treefmtNix = treefmt-nix;
        };
      };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nivisLib.defaultSystems;

      imports = [
        (flakeModules.default {
          srcRoot = ./.;
          # nivis eats its own generated files: the same workflows and
          # dependabot manifest it hands every other repo.
          repo.initialVersion = "0.2.0";
          repo.runner = nivisLib.repo.runners.githubHosted;
          repo.name = "nivis";
          repo.extraFiles = import ./nix/workflows.nix { };
          repo.gitignoreExtra = ''
            # `bun install` in examples/consumer, which is a bun project so the
            # bun module has something to be tested against
            node_modules/
          '';
        })
      ];

      flake = {
        inherit flakeModules;
        lib = nivisLib;
      };

      perSystem = { pkgs, mkDevShell, ... }: {
        devShells.default = mkDevShell {
          packages = [ pkgs.nixd ];
        };
      };
    };
}
