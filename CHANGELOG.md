# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) — where "API" means
the flake modules, their import-time parameters, the `_module.args` they
publish, and `nivis.lib`.

Consumers should pin a tag rather than tracking `master`; see the README.

## [Unreleased]

### Added

- `examples/standalone`, a second integration test that imports a single
  module rather than `flakeModules.default`, so the individual modules stay
  usable on their own.
- Scheduled `Update flake.lock` workflow, which re-locks the examples against
  the new root lockfile.
- `aarch64-linux` runner in CI, and a step asserting the example lockfiles did
  not drift during the check.
- `CHANGELOG.md` and a repo-level `CLAUDE.md`.

### Changed

- `flakeModules.git-hooks` and `flakeModules.shell` now import the peers whose
  config they read, so importing either on its own evaluates. Every module
  carries an explicit `key` so the repeated arrivals collapse to one instance.
- `modules/treefmt.nix` formats Nix with `nixfmt` (RFC 166) instead of the
  unmaintained `nixpkgs-fmt`. **Consumers will see a whole-tree reformat on
  first `nix fmt`.**
- `examples/consumer` moved its assertions from `packages.default` to `checks`,
  which is what `nix flake check` actually builds, and now asserts that
  `srcExcludes` really drops a directory.

### Removed

- `x86_64-darwin` from `nivisLib.defaultSystems`.
