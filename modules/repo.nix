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
  initialVersion ? "0.0.0",
}:
{ lib, self, ... }:
let
  files = nivisLib.repo.repoFiles {
    inherit
      runner
      ecosystems
      release
      initialVersion
      ;
  };
  paths = lib.attrNames files;

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
        staged = pkgs.linkFarm "nivis-repo-files" (
          lib.mapAttrsToList (name: text: {
            name = name;
            path = pkgs.writeText (lib.replaceStrings [ "/" ] [ "-" ] name) text;
          }) files
        );

        quoted = lib.concatStringsSep " " (map lib.escapeShellArg paths);
      in
      {
        apps.sync-repo.program = lib.getExe (mkRootedApp {
          name = "sync-repo";
          text = ''
            for f in ${quoted}; do
              mkdir -p "$(dirname "$f")"
              install -m 644 "${staged}/$f" "$f"
              echo "wrote $f"
            done
            echo
            echo "Review and commit. These files are generated — edit them in nivis,"
            echo "not here, or the next sync-repo overwrites your changes."
          '';
        });

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
