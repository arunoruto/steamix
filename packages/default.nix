# Everything Steamix ships that is not a NixOS module: the two daemons the
# module can drive but nixpkgs does not package, the Decky plugin scope, and
# what the handheld hardware modules (hardware/) build on.
#
# Takes a plain nixpkgs `pkgs` and returns an attrset shaped like what the
# overlay adds — so the same file backs `overlays.default` and the flake's
# `packages` output.
{ pkgs }:
let
  armadaSource = pkgs.callPackage ./armada-source.nix { };

  linux_armada = pkgs.callPackage ./linux-armada/package.nix {
    armadaSource = pkgs.callPackage ./armada-source.nix { kernelOnly = true; };
    # What nixpkgs gives its own kernels.
    kernelPatches = with pkgs.kernelPatches; [
      bridge_stp_helper
      request_key_helper
    ];
  };
in
{
  steamos-manager = pkgs.callPackage ./steamos-manager/package.nix { };
  decky-loader = pkgs.callPackage ./decky-loader/package.nix { };

  # Snapdragon handhelds, from Armada OS's pinned source (./armada-source.nix):
  # its kernel, the device firmware it carries and the ROCKNIX bootloader.
  # aarch64-linux only; see hardware/.
  inherit linux_armada;
  linuxPackages_armada = pkgs.linuxPackagesFor linux_armada;
  armada-firmware = pkgs.callPackage ./armada-firmware/package.nix { inherit armadaSource; };

  # Valve's native ARM64 Steam client, until nixpkgs' steam has one.
  # aarch64-linux, unfree.
  steam-arm = pkgs.callPackage ./steam-arm/package.nix { };
  rocknix-abl = pkgs.callPackage ./rocknix-abl/package.nix { inherit armadaSource; };

  # pkgs.deckyPlugins.*: buildDeckyPlugin plus one directory per packaged
  # plugin, auto-discovered. The Steamix module's `decky-loader.plugins`
  # option consumes these, mix-and-matchable with store-installed plugins.
  deckyPlugins = pkgs.lib.makeScope pkgs.newScope (
    self:
    pkgs.lib.packagesFromDirectoryRecursive {
      inherit (self) callPackage newScope;
      directory = ./deckyPlugins;
    }
  );
}
