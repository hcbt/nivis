# `nix run .#sync-repo` — writes the shared GitHub-side files into the repo
# that imports this module, and `checks.repo-files-current` fails when what is
# committed has drifted from what nivis would write.
#
# Generating them at eval time and stopping there would not work: GitHub reads
# workflows and dependabot.yml from the repository's own default branch, not
# from a flake output. So the files are committed like any other, and this
# module is what keeps every repo's copy identical without anyone editing seven
# of them by hand. Changing a workflow means changing it here and re-running
# the app.
{ nivisLib, treefmtNix }:
{
  # Off for a flake that is not itself a repo — the examples in this tree are
  # subdirectory flakes, and GitHub reads none of these files from there.
  enable ? true,
  runner ? nivisLib.repo.runners.githubHosted,
  ecosystems ? [ ],
  release ? true,
  checks ? false,
  initialVersion ? "0.1.0",
  # The project's own generated files, { "path" = "text"; }. See lib/repo.nix.
  extraFiles ? { },
  # Repo name, for the LICENSE copyright line.
  name ? null,
  # Project-specific .gitignore entries, appended to the shared base.
  gitignoreExtra ? "",
}:
{ lib, self, ... }:
let
  files = nivisLib.repo.repoFiles {
    inherit
      runner
      ecosystems
      release
      checks
      initialVersion
      extraFiles
      name
      gitignoreExtra
      ;
  };
  paths = lib.attrNames files;

  # State a tool owns, not configuration nivis owns: written once for a repo
  # that has none, then left alone. Comparing these would fail the drift check
  # the first time the tool updated its own file.
  seeds = nivisLib.repo.seedFiles { inherit release initialVersion; };
  seedPaths = lib.attrNames seeds;

  # The consuming flake's own source. Read through `self` rather than nivis'
  # `src` arg so this module stays importable without `flakeModules.lib`.
  selfSrc = self;
in
{
  key = "nivis:repo";

  imports = [
    # `extraFiles` are generated, so treefmt must leave them alone — prettier
    # reformatting a generated workflow puts the committed copy permanently at
    # odds with what this module writes, and no edit satisfies both. Defining
    # that exclusion means defining a treefmt option, so the module that
    # declares it has to be imported here. Same shape as git-hooks importing
    # its peer; the `key` attributes collapse the duplicate under `default`.
    (import ./treefmt.nix { inherit treefmtNix nivisLib; })
  ];

  perSystem =
    { pkgs, mkShellApp, ... }:
    lib.optionalAttrs enable (
      let
        # Each file is written to the store first and copied out by path, rather
        # than heredoc'd into the script: the contents include `$${{ … }}`,
        # backticks and quotes that a shell would otherwise interpret.
        stage =
          label: set:
          pkgs.linkFarm label (
            lib.mapAttrsToList (name: text: {
              name = name;
              path = pkgs.writeText (lib.replaceStrings [ "/" ] [ "-" ] name) text;
            }) set
          );

        staged = stage "nivis-repo-files" files;
        stagedSeeds = stage "nivis-repo-seeds" seeds;

        quoted = lib.concatStringsSep " " (map lib.escapeShellArg paths);
        quotedSeeds = lib.concatStringsSep " " (map lib.escapeShellArg seedPaths);

        # Deliberately NOT mkRootedApp: that roots at the git toplevel, which is
        # the wrong directory for a flake that lives in a subdirectory of a
        # larger repo — a template inside a catalog would have its files
        # written to the catalog root instead of its own. Walk up to the
        # nearest flake.nix instead, which is this flake's root either way.
        syncRepo = mkShellApp {
          name = "sync-repo";
          text = ''
            root="$PWD"
            while [ ! -e "$root/flake.nix" ]; do
              if [ "$root" = "/" ]; then
                echo "no flake.nix in $PWD or any parent" >&2
                exit 1
              fi
              root="$(dirname "$root")"
            done
            cd "$root"
            echo "syncing $root"

            for f in ${quoted}; do
              mkdir -p "$(dirname "$f")"
              install -m 644 "${staged}/$f" "$f"
              echo "wrote $f"
            done
            # shellcheck disable=SC2043  # one seed today, a list in general
            for f in ${quotedSeeds}; do
              if [ -e "$f" ]; then
                echo "kept $f (seeded once, owned by the tool that writes it)"
                continue
              fi
              mkdir -p "$(dirname "$f")"
              install -m 644 "${stagedSeeds}/$f" "$f"
              echo "seeded $f"
            done
            echo
            echo "Review and commit. The generated files are edited in nivis,"
            echo "not here, or the next sync-repo overwrites your changes."
          '';
        };
      in
      {
        # Generated, so treefmt must not touch them. Both forms, for the same
        # reason `formatterExcludes` carries both: treefmt matches a bare path
        # against the project root only.
        treefmt.settings.global.excludes =
          let
            e = lib.attrNames extraFiles;
          in
          e ++ map (x: "**/" + x) e;

        apps.sync-repo.program = lib.getExe syncRepo;

        # `nix flake check` evaluates apps but never builds them, so a script
        # that fails writeShellApplication's shellcheck pass is only discovered
        # by whoever runs it. Naming it as a check builds it — this exact
        # failure shipped once already.
        checks.sync-repo = syncRepo;

        # nivis itself takes the defaults for every option, so a parameter that
        # `repoFiles` accepts but this module forgets to forward evaluates fine
        # here and fails in the first consumer that sets it — which is how
        # `nixPreinstalled` reached stakles broken. Generating the files with
        # every option flipped is what exercises the whole signature.
        checks.repo-files-all-options = stage "nivis-repo-files-all-options" (
          nivisLib.repo.repoFiles {
            runner = nivisLib.repo.runners.selfHosted;
            ecosystems = [
              {
                ecosystem = "npm";
                # Both `ignore` forms, since the bare one and the
                # version-constrained one render differently.
                ignore = [
                  { dependency = "@playwright/test"; }
                  {
                    dependency = "typescript";
                    versions = [ "7.x" ];
                  }
                ];
              }
            ];
            release = true;
            checks = true;
            initialVersion = "9.9.9";
            # A parameter this module accepts but never forwards evaluates fine
            # in nivis and breaks in the first consumer that sets it — how
            # `nixPreinstalled` reached stakles broken.
            extraFiles = {
              ".github/workflows/example.yml" = "name: example\n";
            };
            name = "example";
            gitignoreExtra = "/dist\n";
          }
        );

        # Facts that must hold across the repo but live in files nivis does not
        # own. Without these the only thing keeping them true is remembering,
        # and each has already been wrong at least once.
        checks.repo-invariants =
          pkgs.runCommand "repo-invariants"
            {
              nativeBuildInputs = [
                pkgs.yq-go
                pkgs.ripgrep
              ];
            }
            ''
              cd ${selfSrc}
              status=0

              # 1. A workflow ref on a branch moves under the repo without a
              # version to read. Five of these pointed at @master across the
              # fleet, so a coldstart change reached three repos immediately.
              if [ -d .github/workflows ]; then
                # Anchored so a documentation comment does not count. coldstart's
                # README example is a commented-out `uses:` line, and an
                # unanchored pattern flagged it as a real ref.
                if branchrefs=$(rg -n --no-heading '^\s*(- )?uses: [^ ]+@(master|main|latest|release)$' .github/workflows 2>/dev/null); then
                  echo "workflow refs pinned to a branch, not a version:"
                  echo "$branchrefs"
                  status=1
                fi
              fi

              # 2. A lockfile with no matching dependabot ecosystem is watched
              # by nothing, and says nothing about it — farmville ran that way
              # after its bun migration until the gap was found by hand.
              eco=""
              if [ -f .github/dependabot.yml ]; then
                eco=$(yq -r '.updates[].package-ecosystem' .github/dependabot.yml | tr '\n' ' ')
              fi
              want() {
                if [ -e "$1" ] && ! echo " $eco " | grep -q " $2 "; then
                  echo "$1 present but dependabot declares no '$2' ecosystem"
                  status=1
                fi
              }
              want bun.lock bun
              want composer.lock composer
              want go.sum gomod
              want Cargo.lock cargo
              want uv.lock uv
              want backend/uv.lock uv

              [ "$status" = 0 ] && echo "repo invariants hold" > $out
              exit $status
            '';

        # `repo-files-all-options` proves the workflows RENDER; nothing proved
        # what they trigger on. A push trigger of `"**"` fires alongside
        # `pull_request` on the same commit, and the concurrency group cannot
        # dedupe them because `github.ref` differs between the two events — so
        # every job runs twice, in every consumer, and the only symptom is a
        # runner bill. That is not a failure any check would otherwise catch.
        checks.repo-files-triggers =
          let
            # Both variants, since `nixPreinstalled` inserts a step into the
            # same indentation-sensitive block.
            rendered = lib.mapAttrsToList (name: args: pkgs.writeText name (nivisLib.repo.nixCheck args)) {
              "nix-check-hosted.yml" = {
                runner = "ubuntu-latest";
                nixPreinstalled = false;
              };
              "nix-check-selfhosted.yml" = {
                runner = "nix-x64";
                nixPreinstalled = true;
              };
            };
          in
          pkgs.runCommand "repo-files-triggers" { nativeBuildInputs = [ pkgs.yq-go ]; } ''
            for f in ${lib.concatStringsSep " " rendered}; do
              # Parsed rather than grepped: a trigger block that renders as
              # invalid YAML is the other half of what can go wrong here, and
              # `repo-files-current` compares text without ever parsing it.
              # `-I=0` keeps the JSON on one line so this stays a string compare.
              branches="$(yq -o=json -I=0 '.on.push.branches' "$f")"
              if [ "$branches" != '["master"]' ]; then
                echo "$f: push triggers on $branches, not [\"master\"] alone." >&2
                echo "A branch with an open PR would run every job twice." >&2
                exit 1
              fi
              # The other half of the contract: dropping `pull_request` would
              # leave a PR branch with no CI at all.
              yq -e '.on | has("pull_request")' "$f" > /dev/null
            done
            touch $out
          '';

        # A repo whose committed copies have drifted fails its own CI, which is
        # the only thing making "identical files per repo" true rather than
        # aspirational.
        checks.repo-files-current = pkgs.runCommand "repo-files-current" { } ''
          status=0
          for f in ${quoted}; do
            if ! [ -e "${staged}/$f" ]; then continue; fi
            if ! diff -u "${staged}/$f" "${selfSrc}/$f" > "$TMPDIR/diff" 2>/dev/null; then
              echo "drifted from nivis: $f"
              cat "$TMPDIR/diff" || true
              status=1
            fi
          done
          if [ "$status" -ne 0 ]; then
            echo
            echo "Run 'nix run .#sync-repo' and commit the result."
            exit 1
          fi
          touch $out
        '';
      }
    );
}
