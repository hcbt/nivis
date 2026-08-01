# The whole scaffolding as one import. Takes the same parameters as
# ./lib.nix, since that is the only piece a project has to configure.
#
# Every module is still named explicitly even though git-hooks and shell now
# pull their own peers in: this list is what the README documents, and the
# duplicate arrivals collapse on the modules' `key` attributes.
{
  nivisLib,
  gitHooks,
  treefmtNix,
}:
args: {
  imports = [
    (import ./lib.nix { inherit nivisLib; } args)
    (import ./git-hooks.nix { inherit gitHooks treefmtNix nivisLib; })
    (import ./treefmt.nix { inherit treefmtNix nivisLib; })
    (import ./shell.nix { inherit nivisLib gitHooks treefmtNix; })
    (import ./repo.nix { inherit nivisLib treefmtNix; } (args.repo or { }))
  ];
}
