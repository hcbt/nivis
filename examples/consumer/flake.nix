{
  description = "Minimal nivis consumer, used as an integration test";

  inputs.nivis.url = "path:../..";

  # flake-parts builds `pkgs` from the CONSUMING flake's own nixpkgs input, so
  # this cannot be dropped. Point it somewhere else to pin nixpkgs yourself.
  inputs.nixpkgs.follows = "nivis/nixpkgs";

  outputs =
    inputs@{ nivis, ... }:
    nivis.inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nivis.lib.defaultSystems;

      imports = [
        (nivis.flakeModules.default {
          srcRoot = ./.;
          srcExcludes = [ "/scratch" ];
          # A subdirectory flake is not a repo — GitHub reads none of the
          # generated files from here.
          repo.enable = false;
          devTools = pkgs: [ pkgs.jq ];
        })
      ];

      perSystem =
        {
          pkgs,
          config,
          src,
          mkApp,
          mkRootedApp,
          mkDevShell,
          ...
        }:
        {
          # Everything that has to actually run lives under `checks`: those are
          # the only outputs `nix flake check` builds. A `packages.default` with
          # assertions in it is evaluated and never built, so its assertions
          # would never fail.
          checks = {
            # Exercises `src` in both directions. `scratch/keep` is committed
            # next to this flake, so the second assertion goes red the moment
            # `srcExcludes` stops being applied — without it the exclusion is
            # untested, since nothing else in this tree matches it.
            src = pkgs.runCommand "check-src" { } ''
              test -f ${src}/flake.nix
              test ! -e ${src}/scratch
              touch $out
            '';

            # Exercises `mkRootedApp` / `devTools`: building the app runs
            # writeShellApplication's shellcheck pass over the generated script.
            probe = mkRootedApp {
              name = "probe";
              text = ''
                jq --version
              '';
            };

            shell = config.devShells.default;
          };

          packages.default = pkgs.runCommand "example-consumer" { } ''
            mkdir -p $out/bin
            printf '#!/bin/sh\necho ok\n' > $out/bin/example-consumer
            chmod +x $out/bin/example-consumer
          '';

          # Exercises `mkApp` at the flake-output level.
          apps.probe = mkApp {
            name = "probe";
            text = ''
              jq --version
            '';
          };

          # Exercises the project-side half of the merge: nivis enabled nixfmt
          # and prettier, this adds a formatter on top.
          treefmt.programs.shfmt.enable = true;

          # Exercises the same merge for hooks.
          pre-commit.settings.hooks.check-executables-have-shebangs.enable = true;

          devShells.default = mkDevShell {
            packages = [ pkgs.jq ];
            env.EXAMPLE_CONSUMER = "1";
          };
        };
    };
}
