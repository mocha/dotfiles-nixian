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
    rev = "70c071b52420563d56b933703ab0442c829b2eb6";
    sha256 = "085nv8w2fhi5g4q15swmjf9xqwlcrdflxg9c10jllaxj8z8fvbik";
  };
in
callPackage "${src}/default.nix" { }
