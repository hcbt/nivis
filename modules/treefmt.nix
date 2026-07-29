# One formatter for every language in the repo. treefmt-nix's flake module
# gives `nix fmt`, a `checks.treefmt` that fails on unformatted files, and a
# single `treefmt` binary the git hooks reuse — so formatting is defined once
# rather than repeated per tool in three places.
#
# Only the language-agnostic half lives here: nix, plus prettier for the
# markup every repo carries. A project enables its own formatters in its own
# module and the two sets merge.
{ treefmtNix, nivisLib }:
{ ... }:
{
  imports = [ treefmtNix.flakeModule ];

  perSystem = {
    treefmt = {
      # Without this treefmt walks up looking for a VCS root and can format
      # outside the flake when it is evaluated from a subdirectory.
      projectRootFile = "flake.nix";

      programs = {
        nixpkgs-fmt.enable = true;
        prettier.enable = true;
      };

      settings.global.excludes = nivisLib.baseFormatterExcludes;
    };
  };
}
