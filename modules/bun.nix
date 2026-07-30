# Bun dependencies in the build sandbox, via
# [bun2nix](https://github.com/nix-community/bun2nix).
#
# nixpkgs ships `bun` but no dependency fetcher: there is no `bun.fetchDeps`
# answering to `pnpm.fetchDeps` or `fetchNpmDeps`, and `bun.passthru` carries
# only `sources` and `updateScript`. Nothing can put a bun project's
# dependencies in front of an offline `bun install` without a Nix expression
# derived from the lockfile — that expression is `bun.nix`, bun2nix generates
# it, and it is a committed file because Nix cannot read the lockfile's hashes
# at build time.
#
# Which means the same drift risk `flakeModules.repo` exists for: a generated
# file that is committed can fall behind what regenerating it would produce.
# `apps.sync-bun-nix` writes it and `checks.bun-nix-current` fails when the
# committed copy no longer matches the lockfile.
#
# This is language-specific, so it is deliberately NOT part of
# `flakeModules.default`. A bun project imports it *alongside* `default` —
# `mkShellApp` comes from `flakeModules.lib`, exactly as `flakeModules.repo`
# takes it.
{ bun2nix }:
{
  # Both are paths relative to the consuming flake's root, read through `self`.
  bunNix ? "bun.nix",
  lockfile ? "bun.lock",

  # bun2nix' escape hatch for a dependency that cannot be installed as
  # published — a function per `bun.nix` key, taking the fetched package and
  # returning a patched one.
  overrides ? { },

  # bun2nix prefetches git and tarball dependencies over the network to hash
  # them, so a lockfile containing any of those cannot be regenerated inside
  # the build sandbox. Registry dependencies carry their hash in `bun.lock`
  # itself and need no network, which is the common case; turn the check off
  # for the project that is not.
  driftCheck ? true,
}:
{ lib, self, ... }:
{
  # Explicit key, like every other module here: the module system deduplicates
  # imports by it, and without one a second arrival would be a distinct
  # anonymous module whose `_module.args` definitions conflict with the first's.
  key = "nivis:bun";

  perSystem =
    {
      pkgs,
      system,
      mkShellApp,
      ...
    }:
    let
      bun2nixPkg = bun2nix.packages.${system}.default;

      lockPath = "${self}/${lockfile}";
      bunNixPath = "${self}/${bunNix}";

      # ONE dependency set per project, shared by every derivation
      # `mkBunDerivation` builds. bun2nix turns each entry in `bun.nix` into its
      # own `fetchurl` — hashes come straight out of `bun.lock`, so unlike
      # `fetchPnpmDeps` or `fetchNpmDeps` there is no aggregate fixed-output
      # hash for anyone to forget to refresh. Regenerating `bun.nix` is the
      # whole of "I changed a dependency".
      bunDeps = bun2nixPkg.fetchBunDeps {
        bunNix = bunNixPath;
        inherit overrides;
      };

      # bun2nix writes to stdout unformatted and without a trailing newline.
      # nivis' treefmt runs nixfmt over every `*.nix` and its end-of-file-fixer
      # hook adds the newline, so a raw copy is rewritten the first time anyone
      # formats the repo — and `checks.bun-nix-current` would then reject the
      # committed file forever. Formatting here with the same `pkgs.nixfmt`
      # treefmt' `programs.nixfmt` uses is what makes "generated" and
      # "formatted" the same bytes.
      #
      # `target` is shell text, not a value to quote: the app writes to a
      # variable and the check to a plain filename.
      generate = lock: target: "bun2nix --lock-file ${lib.escapeShellArg lock} | nixfmt - > ${target}";

      generateTools = [
        bun2nixPkg
        pkgs.nixfmt
      ];

      # Deliberately NOT mkRootedApp, for the reason `sync-repo` is not: that
      # roots at the git toplevel, which is the wrong directory for a flake in a
      # subdirectory of a larger repo — a template inside a catalog would have
      # its `bun.nix` written to the catalog root.
      syncBunNix = mkShellApp {
        name = "sync-bun-nix";
        extraInputs = generateTools;
        text = ''
          root="$PWD"
          while [ ! -e "$root/flake.nix" ]; do
            if [ "$root" = "/" ]; then
              echo "no flake.nix in $PWD or any parent" >&2
              exit 1
            fi
            root="$(dirname "$root")"
          done
          cd "$root"

          if [ ! -e ${lib.escapeShellArg lockfile} ]; then
            echo "no ${lockfile} in $root — run 'bun install' first" >&2
            exit 1
          fi

          # Through a temporary file: a redirect truncates the committed
          # expression before bun2nix has produced a replacement, so a failure
          # would leave the repo with an empty one.
          tmp="$(mktemp)"
          trap 'rm -f "$tmp"' EXIT
          ${generate lockfile ''"$tmp"''}
          install -m 644 "$tmp" ${lib.escapeShellArg bunNix}

          echo "wrote $root/${bunNix} from $root/${lockfile}"
        '';
      };
    in
    {
      _module.args = {
        inherit bunDeps;

        # The toolchain a bun project's dev shell and `devTools` need. bun2nix
        # follows nivis' nixpkgs and a consumer follows it in turn, so this
        # `bun` is the same one bun2nix' hook runs inside the sandbox — dev and
        # build cannot drift onto two bun versions.
        bunTools = [
          pkgs.bun
          bun2nixPkg
        ];

        # The bun2nix package itself, for the parts `mkBunDerivation` does not
        # wrap: `hook`, `fetchBunDeps`, `mkDerivation`, `writeBunApplication`,
        # `writeBunScriptBin`.
        bun2nix = bun2nixPkg;

        # Every JS output a project builds — the production bundle, the unit
        # tests, lint, typecheck — is this one shape, so they all reuse the same
        # `bunDeps` store path instead of each resolving the dependency set
        # again.
        #
        # `src` is the caller's: this module does not import `flakeModules.lib`,
        # because that one is parameterised (`srcRoot`, `srcExcludes`,
        # `devTools`) and importing it here with a second set of parameters
        # would collide with the copy `flakeModules.default` already brought in.
        mkBunDerivation =
          {
            build,
            install ? "touch $out",
            nativeBuildInputs ? [ ],
            ...
          }@args:
          pkgs.stdenv.mkDerivation (
            {
              inherit bunDeps;

              bunInstallFlags = [
                # Platform-specific optional dependencies — `@next/swc-*`,
                # `@tailwindcss/oxide-*`, `@biomejs/cli-*` — are filtered by
                # cpu/os at install time. `bun.nix` carries every variant and
                # the tools resolve their own binary, so install all of them
                # rather than have the build fail on a missing native module.
                "--cpu=*"
                "--linker=isolated"
              ]
              # clonefile, bun's default on darwin, cannot copy out of the Nix
              # store's read-only paths.
              ++ lib.optional pkgs.stdenv.hostPlatform.isDarwin "--backend=symlink";

              # bun2nix' hook otherwise makes `bun test` the check phase.
              # Test runners are their own derivation here, and a project on
              # vitest has no `bun test` suite to run at all.
              dontUseBunCheck = true;

              # `next build` binds a local port. The darwin sandbox denies even
              # loopback without this, and the symptom is a hang rather than an
              # error.
              __darwinAllowLocalNetworking = true;
            }
            // builtins.removeAttrs args [
              "build"
              "install"
              "nativeBuildInputs"
            ]
            // {
              # The hook installs the `bunDeps` cache at `$BUN_INSTALL_CACHE_DIR`
              # and runs `bun install` offline against it before the build, and
              # points `HOME` at a writable temporary directory — which the JS
              # toolchain needs and the sandbox does not otherwise provide.
              nativeBuildInputs = [ bun2nixPkg.hook ] ++ nativeBuildInputs;

              buildPhase = ''
                runHook preBuild
                ${build}
                runHook postBuild
              '';

              installPhase = ''
                runHook preInstall
                ${install}
                runHook postInstall
              '';
            }
          );
      };

      apps.sync-bun-nix.program = lib.getExe syncBunNix;

      checks = {
        # `nix flake check` evaluates apps but never builds them, so a script
        # that fails writeShellApplication's shellcheck pass is only found by
        # whoever runs it. Naming it as a check builds it.
        sync-bun-nix = syncBunNix;
      }
      # The committed expression against what the lockfile says it should be.
      # Forgetting to regenerate is otherwise invisible until a build installs
      # the previous dependency set — silently, because a stale `bun.nix` is a
      # perfectly valid one.
      // lib.optionalAttrs driftCheck {
        bun-nix-current = pkgs.runCommand "bun-nix-current" { nativeBuildInputs = generateTools; } ''
          ${generate lockPath "generated.nix"}

          if ! diff -u ${lib.escapeShellArg bunNixPath} generated.nix; then
            echo
            echo "${bunNix} is not what ${lockfile} generates."
            echo "Run 'nix run .#sync-bun-nix' and commit the result."
            exit 1
          fi

          touch $out
        '';
      };
    };
}
