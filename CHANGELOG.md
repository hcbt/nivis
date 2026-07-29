# Changelog

All notable changes to this project are documented here. Entries from 0.3.0
onward are written by release-please from Conventional Commits — do not edit
them by hand. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) — where "API" means
the flake modules, their import-time parameters, the `_module.args` they
publish, and `nivis.lib`.

Consumers should pin a tag rather than tracking `master`; see the README.

## [0.5.1](https://github.com/hcbt/nivis/compare/v0.5.0...v0.5.1) (2026-07-29)


### Fixed

* **repo:** forward nixPreinstalled from the module to the generator ([#19](https://github.com/hcbt/nivis/issues/19)) ([8b00e67](https://github.com/hcbt/nivis/commit/8b00e67c35ca38ea45909f7664924600689df66d))

## [0.5.0](https://github.com/hcbt/nivis/compare/v0.4.0...v0.5.0) (2026-07-29)


### Added

* **repo:** skip the Nix installer on runners that already have it ([#17](https://github.com/hcbt/nivis/issues/17)) ([325a8f8](https://github.com/hcbt/nivis/commit/325a8f8b36f32b2107e7b8cfb47b5bdb520d00f5))

## [0.4.0](https://github.com/hcbt/nivis/compare/v0.3.2...v0.4.0) (2026-07-29)


### Added

* **repo:** optional generated nix flake check workflow ([#15](https://github.com/hcbt/nivis/issues/15)) ([de5dafb](https://github.com/hcbt/nivis/commit/de5dafbde530a4198f7998d65282386cb0cdaf71))

## [0.3.2](https://github.com/hcbt/nivis/compare/v0.3.1...v0.3.2) (2026-07-29)


### Fixed

* **repo:** let release-please own CHANGELOG.md ([#13](https://github.com/hcbt/nivis/issues/13)) ([dc56dea](https://github.com/hcbt/nivis/commit/dc56dea0d80d0e6fda19bd9df15d69a4fedd40e3))

## [0.3.1](https://github.com/hcbt/nivis/compare/v0.3.0...v0.3.1) (2026-07-29)


### Fixed

* **repo:** stop generating release-please's own state file ([#11](https://github.com/hcbt/nivis/issues/11)) ([ec7d3f9](https://github.com/hcbt/nivis/commit/ec7d3f919ed61921d2718b139ce7f5a8076e2762))

## [0.3.0](https://github.com/hcbt/nivis/compare/v0.2.0...v0.3.0) (2026-07-29)

### Added

- **repo:** generate the shared GitHub files from one place ([#3](https://github.com/hcbt/nivis/issues/3)) ([c35a78f](https://github.com/hcbt/nivis/commit/c35a78faddd41591030900cdc71020e9e03e8a93))

## [0.2.0] - 2026-07-29

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

- `x86_64-darwin` from `nivisLib.defaultSystems`. A consumer that still builds
  for Intel macOS has to pass its own `systems` list.

## [0.1.0] - 2026-07-29

### Added

- Initial flake-parts scaffolding: the git-hooks and treefmt flake modules, the
  `mkShellApp` / `mkRootedApp` / `mkApp` helpers, the cleaned source tree, and
  the dev-shell baseline.

[unreleased]: https://github.com/hcbt/nivis/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/hcbt/nivis/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/hcbt/nivis/releases/tag/v0.1.0
