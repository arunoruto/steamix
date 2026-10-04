# Steamix VM tests, run with the NixOS test driver:
#
#   nix build -L .#checks.x86_64-linux.greetd
#
# Against the NixOS release instead of the locked nixos-unstable (what CI's
# stable channel does):
#
#   nix build -L --no-write-lock-file \
#     --override-input nixpkgs github:nixos/nixpkgs/nixos-26.05 \
#     .#checks.x86_64-linux.greetd
#
# Add `.driverInteractive` and run `result/bin/nixos-test-driver` to poke at
# a test VM by hand.
#
# Takes a plain nixpkgs; Steam is replaced by a stub (./lib.nix), so nothing
# here needs allowUnfree.
{ pkgs }:
let
  testLib = import ./lib.nix { inherit pkgs lib; };
  inherit (pkgs) lib;

  runTest = file: pkgs.testers.runNixOSTest (import file { inherit testLib; });
in
{
  greetd = runTest ./greetd.nix;
  sddm = runTest ./sddm.nix;
  steamos-manager = runTest ./steamos-manager.nix;
  decky-loader = runTest ./decky-loader.nix;

  # Evaluation only: options too simple to need a VM.
  options = import ./options.nix { inherit pkgs testLib; };
}
