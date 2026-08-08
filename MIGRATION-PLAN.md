# Migration plan: nivis to devenv

Draft four. Sections 1 to 4 are settled. Section 6 is the work.

## 1. Decisions

- devenv owns the dev shell, the git hooks and the tasks, in every repo in
  scope.
- **`flake.nix` stays in every repo.** Section 4 has the measurement that
  overturned the original "delete it everywhere".
- coldstart's `mkImage` keeps building the OCI images. devenv's container
  module cannot replace it. Section 5 has the numbers.
- Nix stops managing `.envrc`, `.gitignore`, `LICENSE`, `README`,
  `dependabot.yml` and the workflows.
- release-please goes. `CHANGELOG.md` is deleted in every migrating repo.
- No tags. Inputs pin the default branch. The lock still resolves an exact
  commit, so traceability holds.
- No shared devenv module. Every repo owns its whole `devenv.nix`.
- nivis is not archived. It shrinks to serve stakles, snowplow and coldstart.
- **Out of scope, untouched:** nixplates (pinned at nivis v0.8.2) and
  cloudflare-os (a fork of `cloudflare/cloudflare-os`, where `gh` in the
  working copy resolves to the upstream repository).

## 2. Scope

| Repo        | Visibility | Runner          | Migrates |
| ----------- | ---------- | --------------- | -------- |
| stakles     | private    | `nix-x64`       | yes      |
| snowplow    | public     | `ubuntu-latest` | yes      |
| coldstart   | public     | `ubuntu-latest` | yes      |
| nixzoid     | public     | `ubuntu-latest` | yes      |
| nixcord     | private    | `nix-x64`       | yes      |
| writestupid | private    | `nix-x64`       | yes      |
| nivis       | public     | `ubuntu-latest` | shrinks  |

Private repos must use `nix-x64`. The account has no GitHub-hosted minutes, so
`ubuntu-latest` jobs on a private repo are refused outright.

## 3. What devenv replaces

| nivis today                           | devenv                               |
| ------------------------------------- | ------------------------------------ |
| `mkDevShell`, `baseShellTools`        | `packages`, `enterShell`             |
| `flakeModules.git-hooks` (prek)       | `git-hooks.hooks.*`                  |
| `flakeModules.treefmt`                | `nixfmt-rfc-style`, `prettier` hooks |
| `flakeModules.bun`                    | `languages.javascript.bun`           |
| `mkShellApp`, `mkRootedApp`, `mkApp`  | `scripts.*`, `tasks.*`               |
| `checks.treefmt`, `checks.pre-commit` | `devenv test`                        |

`devenv test` runs `enterTest` and the git hooks. `git-hooks` needs its own
input in `devenv.yaml`. `devenv.lock` plus `devenv update` replaces
`flake.lock` plus the generated `update-flake-lock.yml`.

## 4. Why `flake.nix` stays

Measured, not assumed. Every repo publishes something CI or another flake
consumes:

| Repo        | Publishes                                    | Built by                    |
| ----------- | -------------------------------------------- | --------------------------- |
| stakles     | `nixosConfigurations`, `github-runner-image` | `nix build`                 |
| snowplow    | `lib.mkRunnerImage`, `renderChart`, `chart`  | `nix build`                 |
| coldstart   | `lib.mkImage`, flakeModules, nixosModules    | snowplow imports it         |
| nixzoid     | `overlays`, `nixosModules`, `zomboid-image`  | `nix build`, pushed to GHCR |
| nixcord     | `lib`, `dockerImage`                         | `nix build -L`              |
| writestupid | `apiImage`, `webImage`, `webDist`            | `nix build`                 |
| nivis       | `flakeModules.lib`, `lib`                    | coldstart imports it        |

devenv publishes nothing another flake can import, and has no
`nixosModules`, `overlays` or `nixosConfigurations`.

## 5. Why `mkImage` stays

devenv's `src/modules/containers.nix` declares `name`, `fromImage`, `version`,
`copyToRoot`, `startupCommand`, `entrypoint`, `workingDir`, `defaultCopyArgs`,
`registry`, `maxLayers`, `enableLayerDeduplication` and `layers`, plus `env`.

It has no OCI labels, no exposed ports, no CA certificates, and no way to leave
Nix out. User, uid and gid are hardcoded to `user`, 1000, 1000.

nixzoid's image alone needs `withCacert` (its server reaches Steam over TLS),
`labels."org.opencontainers.image.source"` (what makes the GHCR package inherit
the repo's permissions), a `zomboid` user with home `/data` (where the chart
mounts the volume), `exposedPorts`, and `withNix = false` on an image that is
already about 7G.

## 6. Phases

### P1. devenv on the self-hosted runner — DONE, verifying

Only nixcord, writestupid and stakles run on `nix-x64`.

- [x] `pkgs.devenv` added to `snowplow.images.github-runner-image`
      (stakles [#108](https://github.com/hcbt/stakles/pull/108)). devenv 2.1.2
      is substitutable from cache.nixos.org, so no source build.
- [x] `runner-selftest` gained a devenv probe that builds a throwaway
      environment and runs its `enterTest`.
- [x] The probe caught a real failure: coldstart sets `XDG_RUNTIME_DIR` to
      `$HOME/.run` for skopeo, devenv reads the same variable, and the pod does
      not let the runner write there.
- [x] Fixed by pointing `XDG_RUNTIME_DIR` at `/tmp`
      (stakles [#110](https://github.com/hcbt/stakles/pull/110)).
- [ ] `runner-selftest` green on the rolled-out image.

### P2. nixzoid — the pilot

`mkDevShell` only. Keeps `flake.nix`, its overlay, its NixOS module and
`zomboid-image`. Gains `devenv.yaml` and `devenv.nix`. Drops the nivis input,
release-please, `CHANGELOG.md` and the generated files.

### P3. nixcord

`mkApp`, `mkShellApp`, `mkRootedApp`, `src` and `devTools` become `scripts` and
`tasks`. Runs on `nix-x64`, so P1 must be green.

### P4. writestupid

Also carries bun2nix and services-flake. `languages.javascript.bun` and
`services.*` are the devenv equivalents. The build stays a flake package.

### P5. coldstart, snowplow, stakles

Each keeps `flake.nix` and everything it publishes. Each gains devenv for the
shell and hooks. Each stops calling `mkDevShell` but keeps `defaultSystems`,
and stakles keeps `mkApp` and `src`.

stakles goes last. It deploys the live cluster.

### P6. Shrink nivis

| Path                    | Lines | Reason             |
| ----------------------- | ----- | ------------------ |
| `lib/repo.nix`          | 482   | no generated files |
| `modules/repo.nix`      | 298   | same               |
| `modules/bun.nix`       | 237   | devenv             |
| `modules/git-hooks.nix` | 59    | devenv             |
| `modules/shell.nix`     | 51    | devenv             |
| `modules/treefmt.nix`   | 45    | devenv             |

1172 of 1445 lines. What survives: `flake.nix`, the flake-parts passthrough,
`lib.defaultSystems`, `mkCleanSrc`, and `modules/lib.nix` for stakles' `mkApp`
and `src`.

Only safe after P5, because until then three repos still call `mkDevShell`.

## 7. Risks

1. **Six hand-written workflow sets.** The runner label, the action versions
   and the triggers live in six places with nothing comparing them. This is the
   failure nivis exists to prevent, accepted on purpose.
2. **Two nixpkgs pins per repo.** `flake.nix` and `devenv.yaml` each pin one
   unless `devenv.yaml` follows the flake.
3. **stakles is live.** A broken shell there costs more than anywhere else.
4. **`follows` becomes load-bearing.** Master pins do not dedupe a transitive
   input.
5. **`.devenv` is written into the working directory.** It needs a
   `.gitignore` entry in every repo.
6. **Linear is unavailable.** The workspace is at its free issue limit, so no
   issue was created for this work. Commits carry no `Refs:` line.
