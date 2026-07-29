# CLAUDE.md

nivis is shared flake-parts scaffolding that other hcbt projects consume as a
flake input. It has no application code — the deliverable _is_ the module set,
so a change here is a change to every consumer's build.

## Layout

- `lib/default.nix` — plain values and functions, usable without importing a
  module. Exported as `nivis.lib`.
- `modules/*.nix` — the flake modules. Each is a function of nivis' own inputs
  that returns a flake-parts module. Exported as `nivis.flakeModules.*`.
- `examples/consumer` — integration test importing `flakeModules.default`.
- `examples/standalone` — integration test importing a single module.

## Invariants

- **Modules are partially applied with nivis' own inputs in `flake.nix`.**
  flake-parts threads the _consuming_ flake's `inputs` into every module it
  evaluates, so a module reaching for `inputs.git-hooks` would force every
  consumer to declare git-hooks and treefmt-nix itself.
- **A module that reads a peer's `config` must import that peer**, and every
  module carries an explicit `key`. The module system deduplicates imports by
  `key`; without one, arriving by two routes means two anonymous modules and
  conflicting definitions. `examples/standalone` is what catches a regression
  here.
- **Configuration is import-time parameters, not module options.** An option
  would have to be read out of `config` to build `_module.args`, which
  infinitely recurses the moment a project sets that option in a module that
  also consumes one of the helpers.
- **Assertions belong in `checks`.** `nix flake check` builds `checks` and only
  evaluates `packages` and `apps`, so an assertion inside a `packages.default`
  derivation never runs.

## Working on this repo

- Both examples have to be checked explicitly — `nix flake check` on the root
  never evaluates a subdirectory flake:

  ```
  nix flake check
  nix flake check ./examples/consumer
  nix flake check ./examples/standalone
  ```

- New files must be `git add`ed before any `nix` command sees them.
- Changing `nivisLib.defaultSystems` means changing the CI matrix in
  `.github/workflows/test.yml` to match; a system with no runner is a system
  nothing checks.
- Anything that changes the module surface, the parameters, or `nivis.lib` goes
  in `CHANGELOG.md` under `[Unreleased]`.

## The generated GitHub files

`flakeModules.repo` owns `.envrc`, `.github/dependabot.yml`, and the
`Update flake.lock` and release-please workflows, for this repo and every
consumer. They are committed files, because GitHub reads workflows from the
repository's default branch rather than from a flake output.

- **Edit them in `lib/repo.nix`, never in the generated file.** Then run
  `nix run .#sync-repo` here and in each consuming repo.
- `checks.repo-files-current` fails on drift, so a hand-edited copy breaks CI.
- The generated paths are in `nivisLib.repo.generatedPaths` and excluded from
  treefmt — prettier reformatting a workflow would leave the committed copy
  permanently at odds with the generator.
- Releases come from release-please. Do not create tags by hand: merging its
  release PR is what tags, which keeps the tag on a commit already on master.
- **Dependabot bumps land in generated files.** Its PRs edit
  `.github/workflows/*.yml`, which `checks.repo-files-current` then rejects —
  correctly, since the committed copy is not the source. Apply the version in
  `lib/repo.nix`, run `sync-repo`, and close the bot's PR. The failing check is
  the signal, not a problem to work around.
