# dictation-toggle, sourced from the nixian-dictation repo (single source of truth).
# The repo's own default.nix (writeShellApplication) + dictation-toggle.sh live in `src`.
#
# To update: push the repo, then bump `rev` and refresh `sha256` via:
#   nix-prefetch-url --unpack https://github.com/mocha/nixian-dictation/archive/<rev>.tar.gz
{ callPackage, fetchFromGitHub }:
let
  src = fetchFromGitHub {
    owner = "mocha";
    repo = "nixian-dictation";
    rev = "3e798167dd611ddfbddee80cdd6b2cee5371382a";
    sha256 = "0mj4h8d7rl1rb8spjh0bh6c4ljjz3vfhka1zfi6ff9z79qncmnl4";
  };
in
callPackage "${src}/default.nix" { }
