# The whole scaffolding as one import. Takes the same parameters as
# ./lib.nix, since that is the only piece a project has to configure.
{ nivisLib, gitHooks, treefmtNix }:
args:
{
  imports = [
    (import ./lib.nix { inherit nivisLib; } args)
    (import ./git-hooks.nix { inherit gitHooks; })
    (import ./treefmt.nix { inherit treefmtNix nivisLib; })
    (import ./shell.nix { inherit nivisLib; })
  ];
}
