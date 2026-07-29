{
  description = "nivis consumed one module at a time, used as an integration test";

  inputs.nivis.url = "path:../..";
  inputs.nixpkgs.follows = "nivis/nixpkgs";

  outputs =
    inputs@{ nivis, ... }:
    nivis.inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nivis.lib.defaultSystems;

      # `flakeModules.shell` only — no `default`, no `lib`. It is the deepest
      # node in the dependency graph: `mkDevShell` reads config from both
      # git-hooks and treefmt, and git-hooks in turn reads config from treefmt.
      # If any module stopped importing the peers it reads from, this flake
      # would fail to evaluate, which is what makes the README's claim that the
      # modules are usable individually a tested one rather than a promise.
      imports = [ nivis.flakeModules.shell ];

      perSystem =
        {
          pkgs,
          config,
          mkDevShell,
          ...
        }:
        {
          devShells.default = mkDevShell { packages = [ pkgs.hello ]; };

          checks.shell = config.devShells.default;
        };
    };
}
