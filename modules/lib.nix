# Shared building blocks, published through `_module.args` so every other
# module — nivis' own and the consuming project's — takes exactly what it needs
# as a `perSystem` argument instead of reaching into a common `let`.
#
# Configuration arrives as import-time parameters rather than module options on
# purpose. An option would have to be read out of `config` to build
# `_module.args`, and every module that takes one of these args would then need
# `_module.args` evaluated before its own config could be read — an infinite
# recursion the moment a project sets the option in a module that also consumes
# one of the helpers.
{ nivisLib }:
{ srcRoot
, srcExcludes ? [ ]
, devTools ? _pkgs: [ ]
}:
{ lib, ... }:
let
  src = nivisLib.mkCleanSrc {
    src = srcRoot;
    excludes = srcExcludes;
  };
in
{
  perSystem = { pkgs, ... }:
    let
      # Toolchain the apps shell out to. Wrapped into each of them, so
      # `nix run` works outside the dev shell.
      allDevTools = [ pkgs.git pkgs.coreutils ] ++ devTools pkgs;

      # Every app is a store script with its tools on PATH, so `nix run` works
      # regardless of what the caller's environment has.
      mkShellApp = { name, text, extraInputs ? [ ] }:
        pkgs.writeShellApplication {
          inherit name text;
          runtimeInputs = allDevTools ++ extraInputs;
        };

      # An app whose body runs from the repo root, so it behaves the same no
      # matter which subdirectory `nix run` was invoked from.
      mkRootedApp = args: mkShellApp (args // {
        text = ''
          cd "$(git rev-parse --show-toplevel)"
          ${args.text}
        '';
      });
    in
    {
      _module.args = {
        inherit src mkShellApp mkRootedApp;
        devTools = allDevTools;

        # `apps.<name> = mkApp { … }` — collapses the
        # `program = lib.getExe (writeShellApplication { … })` ceremony that
        # every app would otherwise repeat.
        mkApp = args: { program = lib.getExe (mkRootedApp args); };
      };
    };
}
