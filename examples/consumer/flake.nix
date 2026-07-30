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
          srcExcludes = [
            "/scratch"
            # `bun install` here is what produces the lockfile the bun module is
            # tested against; the tree the derivations copy in must not carry
            # its output.
            "/node_modules"
          ];
          # A subdirectory flake is not a repo — GitHub reads none of the
          # generated files from here.
          repo.enable = false;
          devTools = pkgs: [ pkgs.jq ];
        })

        # Language-specific, so it is not part of `default` and is imported on
        # top of it. The defaults find `bun.lock` and `bun.nix` at this flake's
        # root, which is where they are.
        (nivis.flakeModules.bun { })
      ];

      perSystem =
        {
          pkgs,
          config,
          src,
          mkApp,
          mkRootedApp,
          mkDevShell,
          bunDeps,
          bunTools,
          mkBunDerivation,
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

            # Exercises `mkBunDerivation` end to end: bun2nix' hook lays the
            # `bunDeps` cache down, `bun install` resolves out of it with no
            # network, and the build then runs a script that cannot work unless
            # the dependency really landed in `node_modules`.
            #
            # `checks.bun-nix-current` and `checks.sync-bun-nix` come from the
            # module itself, so the drift check and the regenerate app are
            # covered here too.
            bun = mkBunDerivation {
              pname = "example-consumer-bun";
              version = "0.1.0";
              inherit src;
              build = ''
                bun index.js | tee out.txt
                grep -qx 'nivis bun ok 1m' out.txt
              '';
              install = "install -Dm644 out.txt $out/out.txt";
            };

            # The one-dependency-fetch-per-project property, executed rather
            # than assumed: a second output must reference the SAME cache. It
            # regressed the moment `mkBunDerivation` built `bunDeps` per call.
            bun-deps-shared =
              let
                other = mkBunDerivation {
                  pname = "example-consumer-bun-other";
                  version = "0.1.0";
                  inherit src;
                  build = "bun index.js > /dev/null";
                };
              in
              pkgs.runCommand "bun-deps-shared" { } ''
                test "${bunDeps}" = "${other.bunDeps}"
                touch $out
              '';
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

          # `bunTools` is the bun module's contribution to a project's shell:
          # bun itself plus the bun2nix CLI, both from the nixpkgs bun2nix'
          # sandbox hook uses, so the shell and the build agree on a version.
          devShells.default = mkDevShell {
            packages = [ pkgs.jq ] ++ bunTools;
            env.EXAMPLE_CONSUMER = "1";
          };
        };
    };
}
