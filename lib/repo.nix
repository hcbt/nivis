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
  formatterExcludes = [
    "CHANGELOG.md"
    ".envrc"
    ".github/dependabot.yml"
    ".github/workflows/nix-check.yml"
    ".github/workflows/update-flake-lock.yml"
    ".github/workflows/release-please.yml"
    "release-please-config.json"
    ".release-please-manifest.json"
  ];

  # Files written only when absent, and never compared. Everything here is
  # state owned by a tool rather than configuration owned by nivis, so a repo's
  # copy is *expected* to diverge from what this generates.
  seedFiles =
    {
      release ? true,
      initialVersion ? "0.0.0",
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
      # Runner label for generated workflows. The self-hosted `nix-x64` has a
      # warm Nix store; GitHub-hosted runners start cold but cover macOS.
      runner ? "ubuntu-latest",
      # Non-Nix package ecosystems dependabot should watch, as
      # { ecosystem = "npm"; directory = "/"; } — `github-actions` is always
      # included, since every repo here has workflows.
      ecosystems ? [ ],
      # Emit the release-please workflow and its config.
      release ? true,
      # Emit a workflow that runs `nix flake check` on push and pull request.
      # Off by default: a repo with CI of its own already runs the checks, and
      # a second workflow would duplicate every build.
      checks ? false,
      # True when `runner` is a self-hosted image that already ships Nix — the
      # snowplow-built runners do. Installing Nix on top of it fails, so the
      # install step is omitted rather than made conditional at run time.
      nixPreinstalled ? false,
    }:
    {
      ".envrc" = envrc;
      ".github/dependabot.yml" = dependabot { inherit ecosystems; };
      ".github/workflows/update-flake-lock.yml" = updateFlakeLock { inherit runner nixPreinstalled; };
    }
    // lib.optionalAttrs checks {
      ".github/workflows/nix-check.yml" = nixCheck { inherit runner nixPreinstalled; };
    }
    // lib.optionalAttrs release {
      ".github/workflows/release-please.yml" = releasePleaseWorkflow { inherit runner; };
      "release-please-config.json" = releasePleaseConfig;
    };

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
      entry =
        {
          ecosystem,
          directory ? "/",
        }:
        ''
          - package-ecosystem: "${ecosystem}"
            directory: "${directory}"
            schedule:
              interval: "weekly"
            commit-message:
              prefix: "chore"
        '';
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
        push:
          branches:
            - "**"

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
  releasePleaseConfig = builtins.toJSON {
    "$schema" = "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json";
    packages.".".release-type = "simple";
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
  };

  releasePleaseManifest = { initialVersion }: builtins.toJSON { "." = initialVersion; };

  # Ignores every repo needs. A project appends its own below the marker that
  # `sync-repo` writes; everything above it is regenerated.
  gitignoreBase = ''
    .direnv/
    result
    result-*
    .DS_Store

    # written by prek when the dev shell is entered
    .pre-commit-config.yaml
  '';
}
