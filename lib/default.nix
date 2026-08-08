# Plain values and functions, usable without importing any flake module.
{ lib }:
rec {
  # Only what something actually checks. `nix flake check` covers the system it
  # runs on, so every entry here needs a runner or it is a support claim nothing
  # verifies.
  #
  # x86_64-darwin: Apple's Intel machines are end of life.
  # aarch64-linux: nothing here targets it — the cluster and its images are
  # x86_64, dev machines are aarch64-darwin — and covering it meant a third
  # hosted runner per job for a platform no output ships to.
  defaultSystems = [
    "x86_64-linux"
    "aarch64-darwin"
  ];

  # Directories excluded from every source tree: machine-specific, and their
  # contents would bust a derivation's input hash on every local build.
  baseSrcExcludes = [ "/.direnv" ];

  # The tree checks and packages copy in. Path-infix based rather than
  # extension based, because what has to be dropped is whole build/cache
  # directories.
  mkCleanSrc =
    {
      src,
      excludes ? [ ],
    }:
    lib.cleanSourceWith {
      inherit src;
      filter =
        path: _type:
        let
          s = toString path;
        in
        !(lib.any (infix: lib.hasInfix infix s) (baseSrcExcludes ++ excludes));
    };
}
