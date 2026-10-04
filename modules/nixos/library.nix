# Games from other launchers in Steam's library, so Gaming Mode can reach
# them: BoilR (github.com/PhilipK/BoilR) finds the games Heroic, Legendary,
# Lutris, itch.io, Bottles, Flatpak and others have installed, and writes
# them into Steam's shortcuts, with artwork from SteamGridDB if given a key.
#
# It runs on every login, inside the Gaming Mode session right before Steam
# starts (steamix.session.preStart). That is the one moment Steam is
# guaranteed to be closed, which BoilR needs: Steam keeps its own copy of the
# library in memory and writes it back on exit. A game installed in Desktop
# Mode therefore appears the next time Gaming Mode starts.
#
# Repeating the sync is safe. BoilR removes only the shortcuts it tagged as
# its own, and any shortcut with the same app id as one it is about to add
# (the same game added by Heroic's own "Add to Steam"); shortcuts added by
# hand are kept.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.steamix.library.boilr;
  toml = pkgs.formats.toml { };

  # Stands in for the SteamGridDB key in the generated file and is replaced
  # at runtime, so the key never enters the Nix store.
  keyPlaceholder = "@steamix-steamgriddb-key@";

  # The configuration, with or without SteamGridDB. Both are generated so a
  # key file that turns out to be unusable at login falls back to a sync
  # without artwork instead of a broken config.
  mkConfig =
    withKey:
    toml.generate "boilr-config${lib.optionalString withKey "-with-key"}.toml" (
      lib.recursiveUpdate {
        steam = {
          # Gaming Mode is Big Picture; its tiles want the wide art.
          optimize_for_big_picture = true;
          # Steamix already runs this while Steam is closed and starts Steam
          # itself afterwards.
          stop_steam = false;
          start_steam = false;
        };
        steamgrid_db = {
          enabled = withKey;
        }
        // lib.optionalAttrs withKey { auth_key = keyPlaceholder; };
      } cfg.settings
    );

  sync = pkgs.writeShellScript "steamix-library-sync" ''
    set -u
    config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/boilr"
    ${pkgs.coreutils}/bin/mkdir -p "$config_dir"

    # The file is written from the configuration on every login, so it is
    # the source of truth: changes made in BoilR's own window do not last.
    tmp="$config_dir/config.toml.steamix"
    ${
      if cfg.steamGridDbKeyFile == null then
        ''
          ${pkgs.coreutils}/bin/install -m 0600 ${mkConfig false} "$tmp"
        ''
      else
        ''
          key=$(${pkgs.coreutils}/bin/tr -d '[:space:]' < ${lib.escapeShellArg cfg.steamGridDbKeyFile} 2>/dev/null || true)
          case "$key" in
            "" | *[!A-Za-z0-9]*)
              echo "steamix: no usable SteamGridDB key in ${cfg.steamGridDbKeyFile}; syncing without artwork" >&2
              ${pkgs.coreutils}/bin/install -m 0600 ${mkConfig false} "$tmp"
              ;;
            *)
              ${pkgs.coreutils}/bin/install -m 0600 ${mkConfig true} "$tmp"
              ${pkgs.gnused}/bin/sed -i "s|${keyPlaceholder}|$key|" "$tmp"
              ;;
          esac
        ''
    }
    ${pkgs.coreutils}/bin/mv "$tmp" "$config_dir/config.toml"

    echo "steamix: syncing other launchers' games into Steam's library with BoilR"
    ${pkgs.coreutils}/bin/timeout ${toString cfg.timeout} ${lib.getExe cfg.package} --no-ui \
      || echo "steamix: BoilR did not finish cleanly (exit $?); starting Steam anyway" >&2
  '';
in
{
  options.steamix.library.boilr = {
    enable = lib.mkEnableOption ''
      syncing games from other launchers (Heroic, Legendary, Lutris, itch.io,
      Bottles, Flatpak, ...) into Steam's library with BoilR, on every login
      before Steam starts, so Gaming Mode can launch them
    '';

    package = lib.mkPackageOption pkgs "boilr" { };

    settings = lib.mkOption {
      inherit (toml) type;
      default = { };
      example = lib.literalExpression ''
        {
          lutris.enabled = false;
          steam.create_collections = true;
          # launch these Heroic games directly instead of through Heroic
          heroic.launch_games_through_heroic = [ "Fortnite" ];
          heroic.default_launch_through_heroic = true;
        }
      '';
      description = ''
        BoilR's configuration, written to `~/.config/boilr/config.toml` on
        every login (see BoilR's
        [configuration reference](https://github.com/PhilipK/BoilR/blob/main/configuration.md)).
        Anything not set keeps BoilR's default, which detects most launchers
        on its own. Steamix sets `steam.optimize_for_big_picture`, and enables
        SteamGridDB only when {option}`steamix.library.boilr.steamGridDbKeyFile`
        is set; both can be overridden here.

        Because the file is rewritten on every login, this is the source of
        truth: changes made in BoilR's own window do not last.
      '';
    };

    steamGridDbKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/steamgriddb";
      description = ''
        A file holding a [SteamGridDB API key](https://www.steamgriddb.com/profile/preferences/api),
        read at login, so the key never enters the Nix store. With it, BoilR
        downloads covers, banners and logos for every game it adds. It must
        be readable by {option}`steamix.user`. `null` syncs without artwork.
      '';
    };

    timeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 120;
      description = ''
        Seconds a sync may take before Steam is started anyway. The first
        sync with artwork downloads images for every game; later ones only
        for new games.
      '';
    };
  };

  config = lib.mkIf (config.steamix.enable && cfg.enable) {
    steamix.session.preStart = "${sync} || true";

    # For running BoilR's window from Desktop Mode, to see what it finds.
    environment.systemPackages = [ cfg.package ];
  };
}
