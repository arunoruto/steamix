# Everything Steamix ships that is not the NixOS module: the two daemons the
# module can drive but nixpkgs does not package, and the Decky plugin scope.
#
# Takes a plain nixpkgs `pkgs` and returns an attrset shaped like what the
# overlay adds — so the same file backs `overlays.default` and the flake's
# `packages` output.
{ pkgs }:
{
  steamos-manager = pkgs.callPackage ./steamos-manager/package.nix { };
  decky-loader = pkgs.callPackage ./decky-loader/package.nix { };

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
