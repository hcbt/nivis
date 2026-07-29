# git-hooks.nix's own flake module, rather than calling `git-hooks.lib.run`
# by hand: it wires `checks.pre-commit-check` and the shell hook that
# materialises `.pre-commit-config.yaml`, and it keeps the hook set in the same
# place as the rest of the flake's configuration.
#
# Only the language-agnostic half lives here. A project adds its own hooks by
# declaring them in its own module — the module system merges the two hook sets,
# so nothing has to be re-stated to extend them.
{
  gitHooks,
  treefmtNix,
  nivisLib,
}:
{ ... }:
{
  key = "nivis:git-hooks";

  imports = [
    gitHooks.flakeModule

    # The treefmt hook below reads `config.treefmt.build.wrapper`, so this
    # module cannot be imported on its own without the module that defines it.
    # Importing the peer here is what makes `flakeModules.git-hooks` usable
    # alone; the explicit keys collapse it back to one instance when
    # `flakeModules.default` pulls in both.
    (import ./treefmt.nix { inherit treefmtNix nivisLib; })
  ];

  perSystem = { config, pkgs, ... }: {
    pre-commit = {
      check.enable = true;

      settings = {
        package = pkgs.prek;

        hooks = {
          # Formatting is treefmt's job — running it as one hook keeps the hook
          # set from drifting away from `nix fmt` and `checks.treefmt`.
          treefmt = {
            enable = true;
            packageOverrides.treefmt = config.treefmt.build.wrapper;
          };

          # Correctness checks that are not formatting.
          check-merge-conflicts.enable = true;
          check-yaml.enable = true;
          check-added-large-files.enable = true;

          # treefmt only touches files it has a formatter for. These two cover
          # everything else — no formatter knows about a .gitignore or a
          # Dockerfile, and a missing trailing newline shows up as a spurious
          # diff line in every later change to the file.
          end-of-file-fixer.enable = true;
          trim-trailing-whitespace.enable = true;
        };
      };
    };
  };
}
