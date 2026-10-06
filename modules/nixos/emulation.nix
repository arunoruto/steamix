# Emulation: RetroArch with a set of libretro cores.
#
# Independent of the rest of Steamix (`steamix.enable`): it also serves
# machines Steam does not run on, such as a Raspberry Pi 4 (no LSE atomics,
# which Valve's ARM64 client needs). There, `kiosk.enable` boots straight
# into RetroArch, full screen.
#
# With Gaming Mode, RetroArch is an application in Desktop Mode; add it to
# Steam as a non-Steam game to reach it from Gaming Mode.
#
# The default cores are free software and cover the 8-, 16- and 32-bit
# classics: NES (Nestopia), SNES (bsnes), Game Boy / Color / Advance (mGBA)
# and PlayStation (PCSX ReARMed). The fastest SNES and Mega Drive cores
# (Snes9x, Genesis Plus GX, PicoDrive) are unfree, for non-commercial use
# only, so they are left to the configuration to add (with unfree packages
# allowed): on small ARM boards they are the ones to pick. Games go in
# ~/ROMs, where RetroArch's file browser starts.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.steamix.emulation;

  retroarch = cfg.retroarch.package.wrapper {
    inherit (cfg.retroarch) cores;
    settings = {
      rgui_browser_directory = "~/ROMs";
    }
    // cfg.retroarch.settings;
  };
in
{
  options.steamix.emulation = {
    enable = lib.mkEnableOption "emulation: RetroArch with a set of libretro cores";

    retroarch = {
      package = lib.mkPackageOption pkgs "retroarch-bare" {
        extraDescription = ''
          The frontend alone; {option}`steamix.emulation.retroarch.cores`
          and {option}`steamix.emulation.retroarch.settings` are wrapped
          around it.
        '';
      };

      cores = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = with pkgs.libretro; [
          nestopia
          bsnes
          mgba
          pcsx-rearmed
        ];
        defaultText = lib.literalExpression ''
          with pkgs.libretro; [ nestopia bsnes mgba pcsx-rearmed ]
        '';
        example = lib.literalExpression ''
          # unfree, but much faster on small ARM boards
          with pkgs.libretro; [ nestopia snes9x genesis-plus-gx mgba pcsx-rearmed ]
        '';
        description = ''
          The libretro cores RetroArch can run, from `pkgs.libretro`. The
          default ones are free software.
        '';
      };

      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        example = {
          video_fullscreen = "true";
          menu_driver = "ozone";
        };
        description = ''
          `retroarch.cfg` settings, applied over the user's own
          configuration on every start, so these always win over what is
          changed in RetroArch's menus.
        '';
      };

      finalPackage = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        default = retroarch;
        defaultText = lib.literalMD "RetroArch with the cores and settings above";
        description = "The RetroArch that is installed.";
      };
    };

    kiosk = {
      enable = lib.mkEnableOption ''
        booting straight into RetroArch, full screen, for machines that run
        nothing else on their display (no Steam, no desktop). It runs as
        {option}`steamix.emulation.kiosk.user` in the cage compositor, and
        is started again if it exits
      '';

      user = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = config.steamix.user;
        defaultText = lib.literalExpression "config.steamix.user";
        description = "The user RetroArch runs as in kiosk mode.";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.systemPackages = [ cfg.retroarch.finalPackage ];
      }

      (lib.mkIf cfg.kiosk.enable {
        assertions = [
          {
            assertion = cfg.kiosk.user != null;
            message = "steamix.emulation.kiosk.enable needs steamix.emulation.kiosk.user (or steamix.user).";
          }
          {
            assertion = !(config.steamix.enable && config.steamix.autoStart);
            message = "steamix.emulation.kiosk.enable and Steamix's Gaming Mode both want the display; enable one of them.";
          }
        ];

        services.cage = {
          enable = true;
          user = cfg.kiosk.user;
          program = "${lib.getExe cfg.retroarch.finalPackage} --fullscreen";
        };
        # Quitting RetroArch ends cage; start both again rather than leave
        # the screen dark until the next boot.
        systemd.services.cage-tty1.serviceConfig = {
          Restart = "always";
          RestartSec = 1;
        };

        hardware.graphics.enable = true;
        # Controllers and keyboards, read through udev.
        users.users = lib.optionalAttrs (cfg.kiosk.user != null) {
          ${cfg.kiosk.user}.extraGroups = [
            "input"
            "video"
          ];
        };
      })
    ]
  );
}
