# nivis' own workflows, as text for `repo.extraFiles`.
#
# The scaffolding follows the rule it gives everyone else: a repo with half its
# workflows generated states the same facts twice and checks only one copy.
# This one is `test.yml`, which is nivis-specific — it runs the matrix across
# both default systems and checks the two example flakes, neither of which any
# consumer has.
#
# Verbatim YAML under `nix/ci/` rather than a Nix string: workflow files
# contain `'${{ … }}'`, and a quote immediately before an interpolation cannot
# be written unambiguously in a Nix indented string. `nix/ci/` is excluded from
# treefmt, or prettier reformats the source while the generated copy stays
# excluded and the two can never match.
{ }:
{
  ".github/workflows/test.yml" = builtins.readFile ./ci/test.yml;
}
