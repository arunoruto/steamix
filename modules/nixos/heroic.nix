# Heroic Games Launcher: Epic, GOG and Amazon Prime Gaming libraries,
# installed next to Steam.
#
# This only installs it, which makes it a normal application in Desktop
# Mode. Gaming Mode shows only what is in Steam's library, so from there a
# game is reached through Heroic's own per-game "Add to Steam" action, or by
# adding Heroic itself as a non-Steam game.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.steamix.heroic;
in
{
  options.steamix.heroic = {
    enable = lib.mkEnableOption "Heroic Games Launcher, for Epic, GOG and Amazon Prime Gaming games";

    package = lib.mkPackageOption pkgs "heroic" {
      extraDescription = ''
        nixpkgs' `heroic` runs the launcher in an FHS environment with the
        libraries its games and Wine builds expect. Use
        `pkgs.heroic.override { extraPkgs = pkgs: [ ... ]; }` to add more.
      '';
    };
  };

  config = lib.mkIf (config.steamix.enable && cfg.enable) {
    environment.systemPackages = [ cfg.package ];
  };
}
