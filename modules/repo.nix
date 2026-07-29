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
{ nivisLib }:
{
  # Off for a flake that is not itself a repo — the examples in this tree are
  # subdirectory flakes, and GitHub reads none of these files from there.
  enable ? true,
  runner ? "ubuntu-latest",
  ecosystems ? [ ],
  release ? true,
  checks ? false,
  initialVersion ? "0.0.0",
}:
{ lib, self, ... }:
let
  files = nivisLib.repo.repoFiles {
    inherit
      runner
      ecosystems
      release
      checks
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

  perSystem =
    { pkgs, mkRootedApp, ... }:
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

        syncRepo = mkRootedApp {
          name = "sync-repo";
          text = ''
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
        apps.sync-repo.program = lib.getExe syncRepo;

        # `nix flake check` evaluates apps but never builds them, so a script
        # that fails writeShellApplication's shellcheck pass is only discovered
        # by whoever runs it. Naming it as a check builds it — this exact
        # failure shipped once already.
        checks.sync-repo = syncRepo;

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
