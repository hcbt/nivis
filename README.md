# nivis

Shared flake-parts scaffolding for hcbt projects. Factors out the modules every
project's flake repeats — git hooks, treefmt, the app helpers, the dev-shell
baseline — so a project declares one input instead of four and keeps only the
parts that are actually language-specific.

## Use

```nix
{
  inputs.nivis.url = "github:hcbt/nivis";

  # flake-parts builds `pkgs` from the CONSUMING flake's own nixpkgs input, so
  # this cannot be dropped. Point it somewhere else to pin nixpkgs yourself.
  inputs.nixpkgs.follows = "nivis/nixpkgs";

  outputs = inputs@{ nivis, ... }:
    nivis.inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = nivis.lib.defaultSystems;

      imports = [
        (nivis.flakeModules.default {
          srcRoot = ./.;
          srcExcludes = [ "/dist" "/bin" ];
          devTools = pkgs: [ pkgs.go ];
        })

        ./nix/packages.nix
        ./nix/checks.nix
        ./nix/apps.nix
        ./nix/shells.nix
      ];
    };
}
```

The project's own modules then extend what nivis set up — the module system
merges the two, so nothing has to be re-stated:

```nix
# nix/treefmt.nix — nivis already enabled nixpkgs-fmt and prettier
{ ... }:
{
  perSystem.treefmt.programs.gofmt.enable = true;
}
```

```nix
# nix/shells.nix — mkDevShell adds prek, the treefmt wrapper, the pinned
# shell utilities, and inputsFrom = [ config.pre-commit.devShell ]
{ ... }:
{
  perSystem = { pkgs, mkDevShell, ... }: {
    devShells.default = mkDevShell {
      packages = [ pkgs.go pkgs.gopls ];
    };
  };
}
```

## What the modules provide

| Module                   | Provides                                                                                                                            |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| `flakeModules.lib`       | `_module.args`: `src`, `devTools`, `mkShellApp`, `mkRootedApp`, `mkApp`.                                                            |
| `flakeModules.git-hooks` | git-hooks.nix flake module, prek as the runner, the treefmt hook, `check-merge-conflicts`, `check-yaml`, `check-added-large-files`. |
| `flakeModules.treefmt`   | treefmt-nix flake module, `projectRootFile`, `nixpkgs-fmt`, `prettier`, the base excludes.                                          |
| `flakeModules.shell`     | `_module.args.mkDevShell`.                                                                                                          |
| `flakeModules.default`   | All four. Takes the same parameters as `flakeModules.lib`.                                                                          |

Parameters, all to `flakeModules.default` / `flakeModules.lib`:

| Parameter     | Required | Default | Purpose                                                                |
| ------------- | -------- | ------- | ---------------------------------------------------------------------- |
| `srcRoot`     | yes      | —       | Directory holding `flake.nix`; the tree checks and packages copy in.   |
| `srcExcludes` | no       | `[]`    | Extra path infixes dropped from that tree, on top of `/.direnv`.       |
| `devTools`    | no       | `_: []` | `pkgs -> [package]`, on PATH in every app alongside git and coreutils. |

`nivis.lib` also exports `defaultSystems`, `baseShellTools`, `baseFormatterExcludes`,
`baseSrcExcludes` and `mkCleanSrc` as plain values, for a project that wants a
piece without the module.

## Design notes

- **Modules are partially applied with nivis' own inputs.** flake-parts threads
  the _consuming_ flake's `inputs` into every module it evaluates, so a module
  reaching for `inputs.git-hooks` would force every consumer to declare
  git-hooks and treefmt-nix itself — most of the boilerplate this exists to
  remove. Closing over them in `flake.nix` is what reduces a consumer to one
  input.
- **Configuration is import-time parameters, not module options.** An option
  would have to be read out of `config` to build `_module.args`, and every
  module taking one of those args would then need `_module.args` evaluated
  before its own config could be read. That is an infinite recursion the moment
  a project sets the option in a module that also consumes a helper.
- **`mkDevShell` does not define `devShells.default`.** The shells this was
  factored out of differ in `env`, `shellHook`, and forced assertions; a module
  owning the output would need an option per difference. Projects keep their own
  `shells.nix`.

## Develop

```
nix develop
nix flake check
nix fmt
```

`examples/consumer` is an integration test: a flake that consumes this one
through `path:../..` and exercises every module.
