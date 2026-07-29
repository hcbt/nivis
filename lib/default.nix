# Plain values and functions, usable without importing any flake module.
{ lib }:
rec {
  defaultSystems = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
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
  mkCleanSrc = { src, excludes ? [ ] }:
    lib.cleanSourceWith {
      inherit src;
      filter = path: _type:
        let s = toString path; in
          !(lib.any (infix: lib.hasInfix infix s) (baseSrcExcludes ++ excludes));
    };
}
