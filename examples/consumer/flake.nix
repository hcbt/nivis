{
  description = "Minimal nivis consumer, used as an integration test";

  inputs.nivis.url = "path:../..";

  # flake-parts builds `pkgs` from the CONSUMING flake's own nixpkgs input, so
  # this cannot be dropped. Point it somewhere else to pin nixpkgs yourself.
  inputs.nixpkgs.follows = "nivis/nixpkgs";

  outputs = inputs@{ nivis, ... }:
    nivis.inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nivis.lib.defaultSystems;

      imports = [
        (nivis.flakeModules.default {
          srcRoot = ./.;
          srcExcludes = [ "/scratch" ];
          devTools = pkgs: [ pkgs.jq ];
        })
      ];

      perSystem = { pkgs, config, src, mkApp, mkDevShell, ... }: {
        # Exercises `src`: the derivation only builds if the cleaned tree
        # actually reached this module.
        packages.default = pkgs.runCommand "example-consumer" { } ''
          test -f ${src}/flake.nix
          mkdir -p $out/bin
          printf '#!/bin/sh\necho ok\n' > $out/bin/example-consumer
          chmod +x $out/bin/example-consumer
        '';

        # Exercises `mkApp` / `mkRootedApp` / `devTools`.
        apps.probe = mkApp {
          name = "probe";
          text = ''
            jq --version
          '';
        };

        # Exercises the project-side half of the merge: nivis enabled
        # nixpkgs-fmt and prettier, this adds a formatter on top.
        treefmt.programs.shfmt.enable = true;

        # Exercises the same merge for hooks.
        pre-commit.settings.hooks.check-executables-have-shebangs.enable = true;

        devShells.default = mkDevShell {
          packages = [ pkgs.jq ];
          env.EXAMPLE_CONSUMER = "1";
        };

        checks.shell = config.devShells.default;
      };
    };
}
