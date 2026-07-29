# nivis

Shared flake-parts scaffolding for hcbt projects. Factors out the modules every
project's flake repeats — git hooks, treefmt, the app helpers, the dev-shell
baseline — so a project declares one input instead of four and keeps only the
parts that are actually language-specific.

## Use

```nix
{
  # Pin a tag. `github:hcbt/nivis` without one tracks master, so a change here
  # lands in the project on its next `nix flake update` with nothing to read
  # about what moved.
  inputs.nivis.url = "github:hcbt/nivis/v0.2.0";

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
# nix/treefmt.nix — nivis already enabled nixfmt and prettier
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

| Module                   | Provides                                                                                                                            | Also pulls in         |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- | --------------------- |
| `flakeModules.lib`       | `_module.args`: `src`, `devTools`, `mkShellApp`, `mkRootedApp`, `mkApp`.                                                            | —                     |
| `flakeModules.git-hooks` | git-hooks.nix flake module, prek as the runner, the treefmt hook, `check-merge-conflicts`, `check-yaml`, `check-added-large-files`. | `treefmt`             |
| `flakeModules.treefmt`   | treefmt-nix flake module, `projectRootFile`, `nixfmt`, `prettier`, the base excludes.                                               | —                     |
| `flakeModules.shell`     | `_module.args.mkDevShell`.                                                                                                          | `git-hooks`,`treefmt` |
| `flakeModules.repo`      | `apps.sync-repo`, `checks.repo-files-current` — the GitHub-side files.                                                              | —                     |
| `flakeModules.default`   | All five. Takes the same parameters as `flakeModules.lib`.                                                                          | —                     |

Each is importable on its own: a module that reads a peer's `config` imports
that peer, and explicit `key` attributes collapse the repeats when several
routes lead to the same module. `examples/standalone` is the test.

Parameters, all to `flakeModules.default` / `flakeModules.lib`:

| Parameter     | Required | Default | Purpose                                                                |
| ------------- | -------- | ------- | ---------------------------------------------------------------------- |
| `srcRoot`     | yes      | —       | Directory holding `flake.nix`; the tree checks and packages copy in.   |
| `srcExcludes` | no       | `[]`    | Extra path infixes dropped from that tree, on top of `/.direnv`.       |
| `devTools`    | no       | `_: []` | `pkgs -> [package]`, on PATH in every app alongside git and coreutils. |

`repo` is an attrset passed straight to `flakeModules.repo`:

| Key               | Default         | Purpose                                                                |
| ----------------- | --------------- | ---------------------------------------------------------------------- |
| `enable`          | `true`          | Off for a flake that is not itself a repo (the examples in this tree). |
| `runner`          | `ubuntu-latest` | Runner label for the generated workflows — e.g. `nix-x64` self-hosted. |
| `ecosystems`      | `[]`            | Extra dependabot ecosystems, `{ ecosystem, directory ? "/" }`.         |
| `release`         | `true`          | Emit the release-please workflow and its config.                       |
| `checks`          | `false`         | Emit a `nix flake check` workflow. Off where the repo has its own CI.  |
| `nixPreinstalled` | `false`         | True for a self-hosted runner whose image already ships Nix.           |
| `initialVersion`  | `"0.0.0"`       | Starting version for a repo release-please has not seen before.        |

`nivis.lib` also exports `defaultSystems`, `baseShellTools`, `baseFormatterExcludes`,
`baseSrcExcludes`, `mkCleanSrc` and `repo` as plain values, for a project that
wants a piece without the module.

## The shared GitHub files

`flakeModules.repo` owns the files Nix cannot: `.envrc`, `.github/dependabot.yml`,
the `Update flake.lock` workflow, and the release-please workflow and config.

```
nix run .#sync-repo   # write them into this repo
```

They are written out and committed rather than left as flake outputs because
GitHub reads workflows and `dependabot.yml` from the repository's own default
branch — a generated file nothing commits is a file Actions never sees.

`checks.repo-files-current` fails when a committed copy has drifted from what
nivis would write, so "every repo carries identical files" is enforced by CI
rather than by remembering. Change a workflow **in nivis**, then re-run
`sync-repo` in each consuming repo. The generated paths are excluded from
treefmt: prettier reformatting a workflow would put the committed copy
permanently at odds with the generator, with no edit able to fix it.

Releases are cut by release-please, not by hand — it maintains `CHANGELOG.md`
from Conventional Commits and opens a release PR whose merge creates the tag.
That also makes the "tagged a branch head a squash-merge then orphaned" mistake
unrepresentable, since the tag can only come from a commit already on master.

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

## Upgrading a project to a new nivis

Bump the pin, then re-enter the dev shell **before** running anything else:

```
nix flake update nivis
nix develop
```

The order matters. Entering the shell is what rewrites the project's generated
`.pre-commit-config.yaml`; until then it still points at the store path built
from the _old_ nivis. A stale one runs the old formatter, so `git commit`
reformats the tree straight back and the hook fails with `files were modified
by this hook` — while `nix flake check` passes, because the flake builds its
config fresh. If that happens, `nix develop` once and re-run.

Upgrading across v0.2.0 also reformats every `.nix` file in the project, since
that release replaced `nixpkgs-fmt` with `nixfmt`. Run `nix fmt` and commit the
result on its own, before any real work, so the reformat does not bury a real
diff.

## Develop

```
nix develop
nix flake check
nix flake check ./examples/consumer
nix flake check ./examples/standalone
nix fmt
```

`nix flake check` on the root never evaluates a subdirectory flake, so both
examples have to be named. Each consumes this flake through `path:../..`:
`consumer` imports `flakeModules.default` and exercises every module,
`standalone` imports a single module and fails if the modules stop being
usable individually.

Releases are tagged and recorded in [CHANGELOG.md](CHANGELOG.md).
