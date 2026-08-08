# Migration: nivis to devenv — done

What was actually done, and what was learned doing it. The forward-looking
plan is kept only where it explains a decision.

## 1. End state

| Repo          | State                                    |
| ------------- | ---------------------------------------- |
| nixzoid       | devenv, master green                     |
| nixcord       | devenv, master green                     |
| coldstart     | devenv, master green                     |
| snowplow      | devenv, master green                     |
| writestupid   | devenv, stack ported to devenv processes |
| stakles       | devenv, runner image carries devenv      |
| nivis         | shrunk to `lib`                          |
| nixplates     | untouched, pinned at nivis `v0.8.2`      |
| cloudflare-os | untouched, pinned at nivis `v0.8.2`      |

Every repo keeps `flake.nix`. devenv owns the dev shell, the git hooks and —
in writestupid — the local stack. release-please, `CHANGELOG.md` and the
generated GitHub files are gone from every migrated repo.

## 2. What overturned the original plan

**`flake.nix` could not go.** Every repo publishes something CI or another
flake consumes: `nixosConfigurations`, `lib.mkImage`, `lib.mkRunnerImage`,
overlays, NixOS modules, and OCI images built with `nix build`. devenv exposes
nothing another flake can import.

**`mkImage` could not go either.** devenv's container module has no OCI
labels, no exposed ports, no CA certificates, and no way to leave Nix out, and
it hardcodes uid 1000. nixzoid's image alone needs four of those five.

**nivis lost every consumer, not three.** The plan had it shrinking to serve
stakles, snowplow and coldstart. All three dropped it outright. Only nixplates
and cloudflare-os still import it, both pinned at the `v0.8.2` tag, so nothing
reads master. What survives is `lib`: `defaultSystems`, `baseSrcExcludes`,
`mkCleanSrc`.

## 3. What cost the most time

**devenv must be built from its own nixpkgs.** `devenv.lib.mkShell` builds
`devenv-tasks` — Rust — out of whatever `pkgs` it is handed, and the binaries
on devenv.cachix.org are built against devenv's own set. Handing it a
project's nixpkgs makes every substituter miss and compiles the crate graph
from source.

**The hook tools must NOT be.** Building `checks.pre-commit` from devenv's
nixpkgs realises a second, uncached closure on the runner — `prettier` alone
drags nodejs. writestupid's `flake` job went from 13 seconds to 22 minutes,
all download, and stakles' from 1m50s to over 10 minutes. Both are back to
normal with the tools coming from each flake's own nixpkgs.

**`--no-pure-eval` is required** for `nix develop` and `nix flake check`,
because devenv reads the working directory. Missing it in a workflow reads as
a repository error: "devenv was not able to determine the current directory".

**The devenv CLI needs `devenv.yaml`.** `devenv.lib.mkShell` reads inputs from
the flake, but `devenv up` and `devenv tasks run` bootstrap devenv themselves.
writestupid needs the CLI for its stack, so it declares inputs twice.

**A module argument cannot default to another module argument.** `modules = [
./devenv.nix ]` makes the module system resolve them, and `toolPkgs ? pkgs`
fails with "attribute 'toolPkgs' missing".

**`enterTest` is not picked up on devenv 2.1.2.** A run logs
`devenv:enterTest (no command)` and then reports "Tests passed", so an
assertion written there passes whether or not it ran. Use `devenv shell` for
anything that must be able to fail.

**ruff follows the current release's default rule set.** No repo here has a
`[tool.ruff]` section, so a nixpkgs bump produced 45 `RUF100` findings and a
pile of `I001` on trees nobody had touched. The rule set is now pinned to
`E4,E7,E9,F` — ruff's documented default — in nixcord and writestupid.

## 4. The stack port

writestupid's `nix run .#services` and `nix run .#e2e` were
process-compose-flake and services-flake graphs. devenv 2.x has no
`depends_on` on a process — ordering is expressed between tasks with `@ready`
and `@succeeded`. So migrate, seed-login and web-deps became tasks, and only
api, worker and web stayed processes with `ready` probes.

`devenv up` replaces `nix run .#services`.
`devenv tasks run writestupid:e2e` replaces `nix run .#e2e`, and devenv stops
every process when the task exits — what `exit_on_end` did.

## 5. Accepted costs

1. **Six hand-written workflow sets.** The runner label, the action versions
   and the triggers live in six places with nothing comparing them. This is
   the failure nivis existed to prevent, accepted on purpose.
2. **Two nixpkgs per repo.** The flake's, and devenv's for its own internals.
3. **writestupid declares inputs twice**, in `flake.nix` and `devenv.yaml`.
4. **No tags.** Inputs pin the default branch; the lock still resolves an
   exact commit.
5. **Linear was unavailable** — the workspace is at its free issue limit, so
   no issue tracks this work and no commit carries a `Refs:` line.
