# Lossless Scaling frame generation for Steam's games, through lsfg-vk
# (https://lsfg-vk.dev), a Vulkan layer that runs Lossless Scaling's frame
# generation using the DLL from your own copy of Lossless Scaling on Steam.
#
# The layer is implicit and global: installed, it loads into every Vulkan
# game, and its config decides where frame generation applies, by profile.
# A profile matches a game by Linux executable, Windows .exe (under Proton),
# process name or Steam App ID.
#
# Two ways to configure it:
#
#   - declaratively, with `profiles`: Steamix writes /etc/lsfg-vk/conf.toml
#     and points the layer at it for every session;
#   - interactively, with `profiles` left empty: the config lives in
#     ~/.config/lsfg-vk/conf.toml, created with defaults on first use and
#     edited with lsfg-vk's UI (`ui.enable`) or the Decky plugin's settings.
#
# nixpkgs has shipped two major versions with different config formats and
# licences: 1.x (MIT, `version = 1`, one [[game]] per executable, LSFG_CONFIG)
# and 2.x (CC BY-NC-ND, so unfree, `version = 2`, [[profile]] with
# `active_in`, LSFGVK_CONFIG). The format follows the installed package.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.steamix.losslessScaling;
  toml = pkgs.formats.toml { };

  isV2 = lib.versionAtLeast (lib.getVersion cfg.package) "2";

  # 2.x rejects unknown keys, so only what each version knows is written.
  configV2 = {
    version = 2;
    global = {
      allow_fp16 = cfg.allowHalfPrecision;
    }
    // lib.optionalAttrs (cfg.dll != null) { inherit (cfg) dll; };
    profile = lib.mapAttrsToList (name: p: {
      inherit name;
      active_in = p.activeIn;
      inherit (p) multiplier;
      flow_scale = p.flowScale * 1.0;
      performance_mode = p.performanceMode;
      pacing_mode = p.pacingMode;
    }) cfg.profiles;
  };

  configV1 = {
    version = 1;
    global = lib.optionalAttrs (cfg.dll != null) { inherit (cfg) dll; };
    game = lib.concatLists (
      lib.mapAttrsToList (
        _: p:
        map (exe: {
          inherit exe;
          inherit (p) multiplier;
          flow_scale = p.flowScale * 1.0;
          performance_mode = p.performanceMode;
          hdr_mode = p.hdrMode;
        }) p.activeIn
      ) cfg.profiles
    );
  };

  configFile = toml.generate "lsfg-vk-conf.toml" (if isV2 then configV2 else configV1);

  # Purely numeric entries are Steam App IDs, which only 2.x matches on.
  appIdEntries = lib.filter (e: builtins.match "[0-9]+" e != null) (
    lib.concatMap (p: p.activeIn) (lib.attrValues cfg.profiles)
  );
  declarative = cfg.profiles != { };

  profileModule = {
    options = {
      activeIn = lib.mkOption {
        type = lib.types.nonEmptyListOf lib.types.str;
        example = [
          "1245620"
          "eldenring.exe"
        ];
        description = ''
          Games this profile applies to: Linux executables (matched as a
          suffix of the path), Windows `.exe` names for Proton games, process
          names, or Steam App IDs. lsfg-vk 1.x matches executables and
          process names only, not Steam App IDs.
        '';
      };

      multiplier = lib.mkOption {
        type = lib.types.ints.between 2 20;
        default = 2;
        description = "Frames shown per rendered frame: 2 doubles the frame rate.";
      };

      flowScale = lib.mkOption {
        type = lib.types.numbers.between 0.25 1;
        default = 1.0;
        description = ''
          Resolution of the motion estimation, as a fraction of the game's.
          Lower is faster and less accurate; on a large display 0.5 to 0.75
          often looks the same.
        '';
      };

      performanceMode = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Use the lighter frame generation model.";
      };

      pacingMode = lib.mkOption {
        type = lib.types.enum [
          "vsync"
          "none"
        ];
        default = "vsync";
        description = "Frame pacing. lsfg-vk 2.x only; ignored by 1.x.";
      };

      hdrMode = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Treat the game's output as HDR. lsfg-vk 1.x only; 2.x detects it.";
      };
    };
  };
in
{
  options.steamix.losslessScaling = {
    enable = lib.mkEnableOption ''
      Lossless Scaling frame generation for Steam's games, through the
      lsfg-vk Vulkan layer. Needs Lossless Scaling installed from Steam; for
      lsfg-vk 2.x, on its "lsfg-vk" beta branch
    '';

    package = lib.mkPackageOption pkgs "lsfg-vk" {
      extraDescription = ''
        From 2.0, lsfg-vk is licensed CC BY-NC-ND 4.0, which nixpkgs treats as
        unfree, so `nixpkgs.config.allowUnfree` (or a predicate allowing
        `lsfg-vk`) has to permit it; the licence also forbids redistribution,
        so no binary cache carries it and it builds locally. NixOS 26.05
        ships the MIT-licensed 1.0, whose config format differs; both work.
      '';
    };

    support32Bit = {
      enable = lib.mkEnableOption ''
        the 32-bit layer as well, for 32-bit games. It is a second local
        build of lsfg-vk
      '';
      package = lib.mkPackageOption pkgs [ "pkgsi686Linux" "lsfg-vk" ] { };
    };

    dll = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/mnt/games/SteamLibrary/steamapps/common/Lossless Scaling";
      description = ''
        Where Lossless Scaling's DLL is, when it is not in a Steam library
        lsfg-vk searches by itself (the default ones under `~/.local/share`
        and `~/.steam`). A directory or the DLL itself. Only written in the
        declarative mode; otherwise set it in the config yourself.
      '';
    };

    allowHalfPrecision = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Use half-precision (FP16) arithmetic where the GPU supports it, for
        2 to 3 times faster frame generation. lsfg-vk 2.x only.
      '';
    };

    profiles = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule profileModule);
      default = { };
      example = lib.literalExpression ''
        {
          elden-ring = {
            activeIn = [ "1245620" ];
            multiplier = 2;
            flowScale = 0.75;
          };
        }
      '';
      description = ''
        Frame generation profiles, by name. When any are set, Steamix writes
        the whole config to `/etc/lsfg-vk/conf.toml` and points every session
        at it, so it is read-only: lsfg-vk's UI and the Decky plugin cannot
        change it. Leave this empty to configure lsfg-vk interactively
        instead, in `~/.config/lsfg-vk/conf.toml`.
      '';
    };

    ui.enable = lib.mkEnableOption ''
      lsfg-vk's configuration UI, for editing profiles from Desktop Mode
      when `profiles` is empty
    '';
  };

  config = lib.mkIf (config.steamix.enable && cfg.enable) {
    # Where implicit Vulkan layers are found, for Steam's runtime included;
    # the gamescope WSI layer is installed the same way.
    hardware.graphics = {
      extraPackages = [ cfg.package ];
      extraPackages32 = lib.mkIf cfg.support32Bit.enable [ cfg.support32Bit.package ];
    };

    environment.etc."lsfg-vk/conf.toml" = lib.mkIf declarative { source = configFile; };

    # 1.x and 2.x read the config path from different variables.
    environment.sessionVariables = lib.mkIf declarative (
      if isV2 then
        { LSFGVK_CONFIG = "/etc/lsfg-vk/conf.toml"; }
      else
        { LSFG_CONFIG = "/etc/lsfg-vk/conf.toml"; }
    );

    environment.systemPackages = lib.mkIf cfg.ui.enable [ pkgs.lsfg-vk-ui ];

    warnings =
      lib.optional (!isV2 && appIdEntries != [ ]) ''
        steamix.losslessScaling.profiles use Steam App IDs
        (${lib.concatStringsSep ", " appIdEntries}), but the installed lsfg-vk
        ${lib.getVersion cfg.package} matches games only by executable or
        process name, so those entries never apply. Use the game's executable
        (for Proton games its .exe name), or lsfg-vk 2.x.
      ''
      ++ lib.optional (declarative && cfg.ui.enable) ''
        steamix.losslessScaling.ui.enable is on while profiles are set: the
        config is then the read-only /etc/lsfg-vk/conf.toml, which the UI
        cannot change. Leave profiles empty to configure lsfg-vk with the UI.
      '';
  };
}
