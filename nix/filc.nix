# pkgs     - ordinary nixpkgs, for tools that run at build and deploy time.
# pkgsFilc - nixpkgs cross-compiled for x86_64-unknown-linux-gnufilc0: every
#            package, libc included, is built with the Fil-C compiler.
#
# This is filnix's `mkPkgsFilc` (its flake.nix) spelled out without flakes, so
# the derivations are the ones https://filc.cachix.org has already built.
{
  system ? "x86_64-linux",
}:
let
  pins = import ./pins.nix;
  pkgs = import pins.nixpkgs {
    inherit system;
    config = { };
    overlays = [ ];
  };
  filcc = import "${pins.filnix}/toolchain.nix" { inherit pkgs; };
in
{
  inherit pkgs;

  pkgsFilc = import pins.nixpkgs {
    localSystem = system;
    crossSystem.config = "x86_64-unknown-linux-gnufilc0";
    config.replaceCrossStdenv = { baseStdenv, ... }: baseStdenv.override { cc = filcc; };
    overlays = [ (import "${pins.filnix}/ports/build-tools.nix") ];
    crossOverlays = [
      (final: prev: { gnufilc0 = filcc; })
      (import "${pins.filnix}/ports/overlay.nix" pkgs)
    ];
  };
}
