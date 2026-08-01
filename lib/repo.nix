# The files every hcbt repo carries that Nix cannot own: direnv's `.envrc`,
# the GitHub workflows, the dependabot manifest, the release-please config.
#
# They live here as strings rather than as files copied out of a directory so a
# consumer's settings — which runner it uses, which package ecosystems it has —
# are applied when the text is built rather than patched afterwards. The
# `sync-repo` app writes the result into the consuming repo, where it is
# committed like any other file: GitHub only reads workflows from the repo's
# own default branch, so generating them at eval time and never writing them
# out would leave nothing for Actions to run.
{ lib }:
rec {
  # Paths treefmt must leave alone: everything `sync-repo` writes, plus the
  # files another tool rewrites on its own schedule.
  #
  # For the generated files, prettier reformatting a workflow would put the
  # committed copy permanently at odds with what nivis generates, failing
  # `checks.repo-files-current` with no edit anyone can make to fix it.
  #
  # CHANGELOG.md is release-please's. It writes its own style on every release,
  # so a formatted CHANGELOG fails `checks.treefmt` on master the moment a
  # release lands — which is exactly how nivis' own 0.3.1 went red.
  formatterExcludes =
    let
      paths = [
        "CHANGELOG.md"
        ".envrc"
        ".github/dependabot.yml"
        ".github/workflows/nix-check.yml"
        ".github/workflows/update-flake-lock.yml"
        ".github/workflows/release-please.yml"
        "release-please-config.json"
        ".release-please-manifest.json"
      ];
    in
    # Both forms: treefmt matches a bare path against the project root only, so
    # a repo that vendors another flake — nixplates' templates/ — would have
    # that flake's generated files reformatted and permanently at odds with
    # what nivis writes.
    paths ++ map (p: "**/" + p) paths;

  # A runner is one decision, not two flags that must agree. `runner` and
  # `nixPreinstalled` were independent: setting `runner = "nix-x64"` and
  # forgetting `nixPreinstalled = true` emits an install-nix step onto an image
  # that already has Nix, and nothing catches the mismatch. A profile carries
  # both, so the pair cannot disagree.
  #
  # Construct a custom one with `mkRunner` when a repo needs a label these do
  # not cover; the fields are the interface.
  mkRunner =
    {
      label,
      nixPreinstalled ? false,
    }:
    {
      inherit label nixPreinstalled;
    };

  runners = {
    # The snowplow-built self-hosted image. Warm Nix store, Nix already
    # present, x86_64-linux only.
    selfHosted = mkRunner {
      label = "nix-x64";
      nixPreinstalled = true;
    };

    # GitHub-hosted. Cold every run and needs Nix installed, but it is the only
    # way to cover macOS and the only option on a repo with no runner
    # registered.
    githubHosted = mkRunner {
      label = "ubuntu-latest";
      nixPreinstalled = false;
    };
  };

  # Files written only when absent, and never compared. Everything here is
  # state owned by a tool rather than configuration owned by nivis, so a repo's
  # copy is *expected* to diverge from what this generates.
  seedFiles =
    {
      release ? true,
      initialVersion ? "0.1.0",
    }:
    lib.optionalAttrs release {
      # release-please rewrites this on every release. Generating it from
      # `initialVersion` and then checking it would fail the drift check on
      # master immediately after the first release, permanently — which is
      # exactly what happened on nivis' own 0.3.0.
      ".release-please-manifest.json" = releasePleaseManifest { inherit initialVersion; };
    };

  # A repo-relative path -> file contents. `sync-repo` overwrites exactly these
  # and `checks.repo-files-current` compares them.
  repoFiles =
    {
      # A runner profile from `runners`, or one built with `mkRunner`. Carries
      # the label and whether the image already ships Nix, so the two cannot
      # disagree.
      runner ? runners.githubHosted,
      # Non-Nix package ecosystems dependabot should watch, as
      # { ecosystem = "npm"; directory = "/"; } — `github-actions` is always
      # included, since every repo here has workflows.
      ecosystems ? [ ],
      # Emit the release-please workflow and its config.
      release ? true,
      # Version for a repo release-please has not released before. Seeds the
      # manifest and sets `initial-version`; both are needed, see below.
      initialVersion ? "0.1.0",
      # Emit a workflow that runs `nix flake check` on push and pull request.
      # Off by default: a repo with CI of its own already runs the checks, and
      # a second workflow would duplicate every build.
      checks ? false,

      # The project's OWN generated files, as { "path" = "text"; }. nivis owns
      # the mechanism — one writer, one drift check, one set of treefmt
      # exclusions — and the project owns the content.
      #
      # This exists because half-generated is worse than either extreme: a repo
      # whose release-please workflow is generated while its test workflow is
      # hand-edited holds the same fact (the runner label, an action version) in
      # two places, and only one of them is checked. The unchecked half is what
      # drifts.
      extraFiles ? { },
      # Repo name, for the LICENSE copyright line. Without it there is nothing
      # to interpolate, so LICENSE is only generated when a name is given.
      name ? null,
      # Project-specific .gitignore entries, appended to the shared base.
      gitignoreExtra ? "",
    }:
    let
      owned = {
        ".envrc" = envrc;
        ".gitignore" = gitignore { extra = gitignoreExtra; };
        ".github/dependabot.yml" = dependabot { inherit ecosystems; };
        ".github/workflows/update-flake-lock.yml" = updateFlakeLock {
          runner = runner.label;
          inherit (runner) nixPreinstalled;
        };
      }
      // lib.optionalAttrs checks {
        ".github/workflows/nix-check.yml" = nixCheck {
          runner = runner.label;
          inherit (runner) nixPreinstalled;
        };
      }
      // lib.optionalAttrs release {
        ".github/workflows/release-please.yml" = releasePleaseWorkflow { runner = runner.label; };
        "release-please-config.json" = releasePleaseConfig { inherit initialVersion; };
      }
      // lib.optionalAttrs (name != null) {
        "LICENSE" = mitLicense { inherit name; };
      };

      clashes = lib.intersectLists (lib.attrNames owned) (lib.attrNames extraFiles);
    in
    # A silent override would defeat the point: the file would still be
    # generated and drift-checked, but against the project's copy rather than
    # nivis', so "every repo carries identical files" would quietly stop being
    # true for that path.
    assert lib.assertMsg (clashes == [ ]) ''
      repo.extraFiles collides with files nivis already generates:
      ${lib.concatMapStringsSep "\n" (p: "  ${p}") clashes}
      Change the workflow in nivis instead, or pick a different path.
    '';
    owned // extraFiles;

  envrc = ''
    # Auto-activate the flake dev shell on `cd` (requires direnv + its shell
    # hook, then a one-time `direnv allow`). Without this, entering the project
    # directory leaves you in the ambient shell — Homebrew/system binaries ahead
    # of nix on PATH — and every command has to be wrapped in `nix develop
    # --command` by hand.
    #
    # Note: direnv activates via a *pre-prompt* hook, so it only fires for
    # interactive shells. Non-interactive one-shot invocations (scripts,
    # tooling, CI) still have to enter the shell explicitly with `nix develop
    # --command …` or `direnv exec . …`.
    use flake
  '';

  # dependabot does not understand flake.lock — the Update flake.lock workflow
  # covers that. What it does cover is everything else a repo pins: the action
  # versions in the workflows, and whatever language lockfiles exist.
  dependabot =
    { ecosystems }:
    let
      # `ignore` is for a dependency whose version is not this repo's to choose:
      # one that must match something Nix supplies, or one deliberately held on
      # a prerelease channel. Without it dependabot reopens the same
      # unmergeable PR every week, and closing it by hand is not a fix — the
      # next run recreates it.
      # Written with explicit "\n" and spaces rather than as a `''` block: the
      # block form strips indentation relative to its least-indented line, so a
      # nested interpolation loses the two levels YAML needs here and the
      # sequence lands at column 0.
      ignoreEntry =
        {
          dependency,
          versions ? [ ],
        }:
        "    - dependency-name: \"${dependency}\""
        + lib.optionalString (versions != [ ]) (
          "\n      versions: [ ${lib.concatMapStringsSep ", " (v: "\"${v}\"") versions} ]"
        );

      entry =
        {
          ecosystem,
          directory ? "/",
          ignore ? [ ],
        }:
        ''
          - package-ecosystem: "${ecosystem}"
            directory: "${directory}"
            schedule:
              interval: "weekly"
            commit-message:
              prefix: "chore"
        ''
        + lib.optionalString (ignore != [ ]) (
          "  ignore:\n" + lib.concatMapStringsSep "\n" ignoreEntry ignore + "\n"
        );
      blocks = map entry ([ { ecosystem = "github-actions"; } ] ++ ecosystems);
    in
    ''
      version: 2

      updates:
      ${lib.concatStringsSep "\n" (map (b: lib.removeSuffix "\n" b) blocks)}
    '';

  updateFlakeLock =
    { runner, nixPreinstalled }:
    ''
      name: Update flake.lock

      on:
        schedule:
          # Mondays, 04:00 UTC.
          - cron: "0 4 * * 1"
        workflow_dispatch:

      permissions:
        contents: write
        pull-requests: write

      jobs:
        update:
          runs-on: ${runner}
          timeout-minutes: 45

          steps:
            - uses: actions/checkout@v7
      ${installNix nixPreinstalled}
            - name: Update the lockfile
              run: nix flake update

            # Pull requests opened with GITHUB_TOKEN do not trigger other
            # workflows, so the repo's own CI does not run on this PR unless a
            # PAT is configured below. The update is checked here instead — an
            # unverified dependency bump is most of what this exists to catch.
            - name: Validate flake outputs
              run: nix flake check

            - uses: peter-evans/create-pull-request@v8
              with:
                branch: update-flake-lock
                title: "chore: update flake.lock"
                commit-message: "chore: update flake.lock"
                labels: dependencies
                body: |
                  Scheduled `nix flake update`. `nix flake check` passed on the
                  runner before this PR was opened.
                # A PAT with `repo` scope as GH_TOKEN_FOR_UPDATES gets the
                # repo's full CI running on these PRs. Without it the PR still
                # opens — provided "Allow GitHub Actions to create and approve
                # pull requests" is enabled in the repository settings — and
                # carries only the check above.
                token: ''${{ secrets.GH_TOKEN_FOR_UPDATES || secrets.GITHUB_TOKEN }}
    '';

  # The install step, or nothing when the runner already has Nix.
  # Written as an escaped string rather than an indented one: `''` strips the
  # common indentation of the block it appears in, so an indented literal here
  # would arrive at column 0 and produce invalid YAML.
  installNix =
    nixPreinstalled:
    lib.optionalString (!nixPreinstalled) "\n      - uses: cachix/install-nix-action@v31\n";

  nixCheck =
    { runner, nixPreinstalled }:
    ''
      name: Check

      on:
        pull_request:
        # Only master. Pushing to a branch that has an open PR fires *both*
        # this and the `pull_request` event on the same commit, and the
        # concurrency group below cannot dedupe them: `github.ref` is
        # `refs/heads/<branch>` for the push but `refs/pull/<n>/merge` for the
        # PR, so they land in different groups and both survive — every job
        # runs twice on the same commit.
        #
        # It also produced a cancelled run on every release: release-please
        # pushes its branch and immediately force-pushes it again, and with
        # `"**"` the first push had already started a run for `cancel-in-progress`
        # to kill.
        #
        # Nothing loses coverage: a branch with a PR is checked by
        # `pull_request`, and master is checked on push. A branch with NO open
        # PR gets no CI until one is opened — the deliberate trade.
        push:
          branches:
            - master

      permissions:
        contents: read

      concurrency:
        group: ''${{ github.workflow }}-''${{ github.ref }}
        cancel-in-progress: true

      jobs:
        check:
          runs-on: ${runner}
          timeout-minutes: 45

          steps:
            - uses: actions/checkout@v7
      ${installNix nixPreinstalled}
            # Everything the flake declares, including the treefmt and hook
            # checks and nivis' repo-files-current.
            - run: nix flake check -L
    '';

  # release-please reads Conventional Commits, maintains CHANGELOG.md, and
  # opens a release PR. Merging that PR is what cuts the tag — which is the
  # point: a tag can only ever be created from a commit that is already on the
  # default branch, so the "tagged a branch head that a squash-merge then
  # orphaned" mistake is not expressible.
  releasePleaseWorkflow =
    { runner }:
    ''
      name: Release

      on:
        push:
          branches:
            - master

      permissions:
        contents: write
        pull-requests: write

      jobs:
        release-please:
          runs-on: ${runner}
          timeout-minutes: 10

          steps:
            - uses: googleapis/release-please-action@v5
              with:
                config-file: release-please-config.json
                manifest-file: .release-please-manifest.json
                token: ''${{ secrets.GH_TOKEN_FOR_UPDATES || secrets.GITHUB_TOKEN }}
    '';

  # `simple` is the release type for a repo with no language-native manifest to
  # bump — it maintains CHANGELOG.md and the tag, and nothing else. The Nix
  # repos here have no version field anywhere that needs rewriting.
  releasePleaseConfig =
    { initialVersion }:
    builtins.toJSON {
      "$schema" = "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json";
      packages.".".release-type = "simple";
      # Without this a repo starting from 0.0.0 jumps to 1.0.0 on its first
      # `feat`, because release-please treats pre-1.0 as a prerelease series to
      # be graduated. These repos stay in 0.x until something deliberately
      # declares a stable interface.
      bump-minor-pre-major = true;
      # feat -> minor, fix -> patch, breaking -> minor while under 1.0. Setting
      # this true would make a feat a patch bump too, which throws away the only
      # signal the commit types carry.
      bump-patch-for-minor-pre-major = false;
      # The bump-*-pre-major options only govern bumping FROM an existing
      # version. A repo release-please has never released is a separate case
      # with its own default of 1.0.0 — which is how stakles' first release PR
      # came out claiming a stable interface.
      initial-version = initialVersion;
      changelog-sections = [
        {
          type = "feat";
          section = "Added";
        }
        {
          type = "fix";
          section = "Fixed";
        }
        {
          type = "perf";
          section = "Performance";
        }
        {
          type = "refactor";
          section = "Changed";
        }
        {
          type = "chore";
          section = "Maintenance";
          hidden = true;
        }
        {
          type = "docs";
          section = "Documentation";
          hidden = true;
        }
      ];
    }
    + "\n";

  # Trailing newline: without it the end-of-file-fixer hook appends one, and
  # the committed copy then differs from what this generates — a file with two
  # owners that no edit can satisfy.
  releasePleaseManifest = { initialVersion }: builtins.toJSON { "." = initialVersion; } + "\n";

  # Ignores every repo needs. A project appends its own below the marker that
  # `sync-repo` writes; everything above it is regenerated.
  gitignoreBase = ''
    .direnv/
    result
    result-*
    .DS_Store

    # written by prek when the dev shell is entered
    .pre-commit-config.yaml

    # per-machine Claude Code state, not shared configuration
    .claude/settings.local.json
  '';

  # The base every repo carries, plus whatever that project genuinely needs.
  # Split rather than hand-maintained: the entries above are the same in every
  # repo and drifted to between 7 and 223 lines when nothing generated them —
  # which is how `.claude/settings.local.json` got committed once.
  gitignore =
    {
      extra ? "",
    }:
    gitignoreBase + lib.optionalString (extra != "") ("\n" + extra);

  # MIT, with the holder line the three repos that already carry it use. The
  # text is identical everywhere except that line, so this generates rather
  # than asking nine repos to hold their own copy.
  mitLicense =
    {
      name,
      year ? "2026",
    }:
    ''
      MIT License

      Copyright (c) ${year} the ${name} authors

      Permission is hereby granted, free of charge, to any person obtaining a copy
      of this software and associated documentation files (the "Software"), to deal
      in the Software without restriction, including without limitation the rights
      to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
      copies of the Software, and to permit persons to whom the Software is
      furnished to do so, subject to the following conditions:

      The above copyright notice and this permission notice shall be included in all
      copies or substantial portions of the Software.

      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
      IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
      FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
      AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
      LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
      OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
      SOFTWARE.
    '';
}
