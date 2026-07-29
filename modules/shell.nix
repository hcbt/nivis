# `mkDevShell`, published through `_module.args`. It does not define
# `devShells.default` itself: the three shells this was factored out of differ
# in env, shellHook and forced assertions, and a module that owned the output
# would have to grow an option for each. Projects keep their own `shells.nix`
# and call this for the parts every shell repeats.
{
  nivisLib,
  gitHooks,
  treefmtNix,
}:
{ ... }:
{
  key = "nivis:shell";

  # `mkDevShell` reads `config.pre-commit.devShell` and
  # `config.treefmt.build.wrapper`, so both peers come along. git-hooks already
  # imports treefmt, but naming it here too keeps the dependency visible at the
  # site that actually uses it — the keys make the repeat free.
  imports = [
    (import ./git-hooks.nix { inherit gitHooks treefmtNix nivisLib; })
    (import ./treefmt.nix { inherit treefmtNix nivisLib; })
  ];

  perSystem = { config, pkgs, ... }: {
    _module.args.mkDevShell =
      {
        packages ? [ ],
        inputsFrom ? [ ],
        ...
      }@args:
      pkgs.mkShell (
        (builtins.removeAttrs args [
          "packages"
          "inputsFrom"
        ])
        // {
          # git-hooks' flake module builds the shell fragment that materialises
          # the generated `.pre-commit-config.yaml` so prek finds its config.
          inputsFrom = [ config.pre-commit.devShell ] ++ inputsFrom;

          packages = [
            pkgs.prek
            # `nix fmt` in the shell, same binary the hooks and check use
            config.treefmt.build.wrapper
          ]
          ++ nivisLib.baseShellTools pkgs
          ++ packages;
        }
      );
  };
}
