# hyprsaver — Wayland-native screensaver for Hyprland (GLSL shaders on
# wlr-layer-shell overlays). Packaged locally because it isn't in nixpkgs and
# its upstream repo is flake-only; this mirrors the flake's buildRustPackage
# but adds a runtime wrapper (see postFixup).
#
# Pinned to tag v0.4.4. To bump: change `version`, then refresh `hash` with
#   nix-prefetch-url --unpack https://github.com/maravexa/hyprsaver/archive/v<ver>.tar.gz
#   | xargs nix-hash --to-sri --type sha256
# and replace Cargo.lock in this directory with the one from that tag.
{ lib
, rustPlatform
, fetchFromGitHub
, pkg-config
, cmake
, makeWrapper
, wayland
, wayland-protocols
, libGL
, libxkbcommon
, mesa
}:

let
  # dlopen'd at runtime — must be on LD_LIBRARY_PATH (see postFixup).
  runtimeLibs = [ wayland libGL libxkbcommon mesa ];
in
rustPlatform.buildRustPackage rec {
  pname = "hyprsaver";
  version = "0.4.4";

  src = fetchFromGitHub {
    owner = "maravexa";
    repo = "hyprsaver";
    rev = "v${version}";
    hash = "sha256-yoordkzrehvVoYZKa+mpXmtp4z3cEFk3ovAlSxb9vQw=";
  };

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ pkg-config cmake makeWrapper ];
  buildInputs = runtimeLibs ++ [ wayland-protocols ];

  PKG_CONFIG_PATH = lib.makeSearchPathOutput "dev" "lib/pkgconfig" [
    wayland
    mesa
    libxkbcommon
  ];

  postInstall = ''
    install -dm755 $out/share/hyprsaver/examples
    [ -d examples/palettes ] && cp -r examples/palettes $out/share/hyprsaver/examples/ || true
    [ -f examples/hyprsaver.toml ] && install -Dm644 examples/hyprsaver.toml \
      $out/share/hyprsaver/examples/hyprsaver.toml || true
  '';

  # libGL / EGL / wayland-egl are dlopen'd at runtime on NixOS; without this the
  # binary builds fine but dies on startup unable to locate them. (Upstream's
  # flake only handles this in its devShell, not the package itself.)
  postFixup = ''
    wrapProgram $out/bin/hyprsaver \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}"
  '';

  meta = with lib; {
    description = "Wayland-native screensaver for Hyprland — GLSL shaders on wlr-layer-shell overlays";
    homepage = "https://github.com/maravexa/hyprsaver";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "hyprsaver";
  };
}
