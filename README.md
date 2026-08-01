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
| `flakeModules.repo`      | `apps.sync-repo`, `checks.repo-files-current`, `checks.repo-invariants` — the GitHub-side files, `LICENSE`, `.gitignore`.           | `treefmt`             |
| `flakeModules.default`   | All five. Takes the same parameters as `flakeModules.lib`.                                                                          | —                     |
| `flakeModules.bun`       | `_module.args`: `mkBunDerivation`, `bunDeps`, `bunTools`, `bun2nix`. Plus `apps.sync-bun-nix` and `checks.bun-nix-current`.         | —                     |

`flakeModules.bun` is the one module **not** in `default`: it is
language-specific, so a bun project imports it on top of `default` rather than
instead of it. See [Bun projects](#bun-projects).

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

| Key              | Default                | Purpose                                                                             |
| ---------------- | ---------------------- | ----------------------------------------------------------------------------------- |
| `enable`         | `true`                 | Off for a flake that is not itself a repo (the examples in this tree).              |
| `runner`         | `runners.githubHosted` | A runner profile — `runners.selfHosted`, or `mkRunner { label; nixPreinstalled; }`. |
| `ecosystems`     | `[]`                   | Extra dependabot ecosystems, `{ ecosystem, directory ? "/", ignore ? [] }`.         |
| `release`        | `true`                 | Emit the release-please workflow and its config.                                    |
| `checks`         | `false`                | Emit a `nix flake check` workflow. Off where the repo has its own CI.               |
| `initialVersion` | `"0.0.0"`              | Starting version for a repo release-please has not seen before.                     |
| `extraFiles`     | `{}`                   | The project's own generated files, `{ "path" = "text"; }`.                          |
| `name`           | `null`                 | Repo name for the generated MIT `LICENSE`. No name, no LICENSE.                     |
| `gitignoreExtra` | `""`                   | Project-specific `.gitignore` entries, appended to the shared base.                 |

`flakeModules.bun` takes its own attrset:

| Key          | Default      | Purpose                                                                          |
| ------------ | ------------ | -------------------------------------------------------------------------------- |
| `bunNix`     | `"bun.nix"`  | The generated expression, relative to the flake root.                            |
| `lockfile`   | `"bun.lock"` | The bun lockfile it is generated from.                                           |
| `overrides`  | `{}`         | bun2nix' per-package patch hook, keyed as in `bun.nix`.                          |
| `driftCheck` | `true`       | Off for a lockfile with git or tarball deps — see [Bun projects](#bun-projects). |

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

An ecosystem entry takes an `ignore` list for a dependency whose version is not
that repo's to choose:

```nix
ecosystems = [
  {
    ecosystem = "bun";
    ignore = [
      # nixpkgs supplies the browsers, so the npm side must follow it.
      { dependency = "@playwright/test"; }
      { dependency = "typescript"; versions = [ "7.x" ]; }
    ];
  }
];
```

Without it dependabot reopens the same unmergeable PR every week, and closing it
by hand is not a fix — the next run recreates it. Each entry renders as
`dependency-name`, plus `versions` when given.

### What a project generates for itself

`extraFiles` puts a project's own files through the same machinery — one
writer, one drift check, one set of treefmt exclusions:

```nix
repo.extraFiles = {
  ".github/workflows/test.yml" = import ./nix/ci/test-workflow.nix { inherit runner; };
};
```

nivis owns the mechanism; the project owns the content. Half-generated is the
worst of the three states: a repo whose release-please workflow is generated
while its test workflow is hand-edited holds the same fact — the runner label,
an action version — in two places, and only one is checked. The unchecked half
is what drifts. A path colliding with one nivis already generates is a hard
error, not a silent override.

### Runners are a profile, not two flags

`runner` and `nixPreinstalled` used to be independent, so `runner = "nix-x64"`
without `nixPreinstalled = true` emitted an install-nix step onto an image that
already had Nix, and nothing caught it. A profile carries both:

```nix
repo.runner = nivis.lib.repo.runners.selfHosted;   # nix-x64, Nix preinstalled
repo.runner = nivis.lib.repo.runners.githubHosted; # ubuntu-latest, installs Nix
repo.runner = nivis.lib.repo.mkRunner { label = "..."; nixPreinstalled = false; };
```

### checks.repo-invariants

Facts that must hold but live in files nivis does not own, so they cannot be
generated:

- no `uses:` in `.github/workflows` pinned to a branch (`@master`, `@main`,
  `@latest`, `@release`)
- every lockfile present has a matching dependabot ecosystem — a `bun.lock`
  with no `bun` ecosystem is watched by nothing and says nothing about it

Releases are cut by release-please, not by hand — it maintains `CHANGELOG.md`
from Conventional Commits and opens a release PR whose merge creates the tag.
That also makes the "tagged a branch head a squash-merge then orphaned" mistake
unrepresentable, since the tag can only come from a commit already on master.

## Bun projects

nixpkgs ships `bun` but no dependency fetcher — there is no `bun.fetchDeps`
answering to `pnpm.fetchDeps` or `fetchNpmDeps`, and `bun.passthru` carries only
`sources` and `updateScript`. Dependencies reach an offline `bun install` through
a Nix expression derived from the lockfile instead, generated by
[bun2nix](https://github.com/nix-community/bun2nix) and committed as `bun.nix`.

```nix
imports = [
  (nivis.flakeModules.default { srcRoot = ./.; srcExcludes = [ "/node_modules" ]; })
  (nivis.flakeModules.bun { })
];
```

```nix
# nix/lib.nix — one shape for every JS output, so they share one dep fetch
{ ... }:
{
  perSystem = { src, mkBunDerivation, ... }: {
    _module.args.mkWorkspaceDerivation = args: mkBunDerivation ({ inherit src; } // args);
  };
}
```

```nix
# nix/checks.nix
lint = mkWorkspaceDerivation {
  pname = "my-app-lint";
  version = "0.1.0";
  build = "bun run lint";
};
```

`mkBunDerivation` is `stdenv.mkDerivation` with bun2nix' setup hook, one
`bunDeps` cache shared by every call, and `build` / `install` as strings instead
of whole phases. Anything else in the attrset goes straight through, so
`bunInstallFlags`, `env`, `dontRunLifecycleScripts` and the rest of the hook's
options are all still reachable. The hook installs the cache, runs
`bun install --ignore-scripts` offline, then runs lifecycle scripts, and points
`HOME` at a writable temporary directory — so a project does not need its own
`export HOME="$TMPDIR"`.

`bunTools` — `bun` plus the bun2nix CLI — is what a dev shell and `devTools`
list. Both come from the nixpkgs bun2nix' sandbox hook uses, which is why
`bun2nix.inputs.nixpkgs` follows nivis': otherwise the shell and the build
install one lockfile with two different bun versions.

### Adding or changing a dependency

```
bun add left-pad          # or bun remove / bun update — anything touching bun.lock
nix run .#sync-bun-nix    # regenerate bun.nix from it
```

Then commit **both** files. `bun.nix` is generated, so it is edited by
regenerating it, never by hand.

`checks.bun-nix-current` fails when the committed `bun.nix` is not what the
current `bun.lock` generates. That check is the whole reason the second command
is not optional: a stale `bun.nix` is a perfectly valid one, so without it a
forgotten regenerate does not error — it silently builds against the previous
dependency set, and `bun install` inside the sandbox has no network to notice
with.

The check regenerates inside the build sandbox, which works because a registry
dependency's hash is already in `bun.lock`. bun2nix has to prefetch git and
tarball dependencies over the network to hash them, so a project with any of
those sets `driftCheck = false` and loses the guarantee.

`nix run .#sync-bun-nix` writes into the nearest enclosing `flake.nix`'s
directory, not the git root — the same reason `sync-repo` does. It formats the
output with the same `nixfmt` `checks.treefmt` uses; raw bun2nix output is
unformatted and unterminated, and would be rewritten by the first `nix fmt`,
which would then fail the drift check with nothing to edit to fix it.

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
