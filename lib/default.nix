# Plain values and functions, usable without importing any flake module.
{ lib }:
rec {
  # The GitHub-side files — workflows, dependabot, release-please, .envrc.
  # Kept in their own file because they are text templates rather than Nix
  # values, and nothing else here needs to read them.
  repo = import ./repo.nix { inherit lib; };

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

  # `nix develop` is IMPURE: it prepends the shell's packages to the ambient
  # PATH rather than replacing it, so any tool NOT pinned here silently falls
  # through to the host's /opt/homebrew or /usr/bin binary. Every shell gets
  # these so the everyday utilities resolve under /nix/store.
  baseShellTools = pkgs: [
    pkgs.git
    pkgs.gh
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.findutils
    pkgs.curl
  ];

  # Lockfiles and binary content: never worth formatting, and prettier will
  # happily mangle some of them.
  baseFormatterExcludes = [
    "*.lock"
    "flake.lock"
    "*.png"
    "*.svg"
    "*.ico"
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
