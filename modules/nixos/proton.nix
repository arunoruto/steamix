# GE-Proton as a Steam compatibility tool, optionally with AMD FSR 4.
#
# FSR 4 is AMD's machine-learning upscaler. GE-Proton can swap it in for
# the FSR 3.1 a game ships: with PROTON_FSR4_UPGRADE set, it downloads AMD's
# amdxcffx64.dll when the game starts and uses it instead. It needs an AMD
# RDNA 3 or RDNA 4 GPU and a game with FSR 3.1; elsewhere it does nothing.
#
# `fsr4.enable` adds a second compatibility tool, "GE-Proton (FSR 4)": the
# same GE-Proton with that flag in front of it, its `proton` launcher wrapped
# in a script that sets the variable and hands over to the original. It has
# its own internal name, so it sits next to any plain GE-Proton (this
# module's or one installed another way) instead of clashing with it. Pick
# it per game in Steam's compatibility settings, or make it Steam's default
# compatibility tool to use it everywhere. The DLL itself is GE-Proton's
# download, not something Nix manages.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.steamix.proton;
  ge = cfg.ge.package;
  src = ge.steamcompattool or ge;

  fsr4Value = if cfg.fsr4.version == null then "1" else cfg.fsr4.version;

  # GE-Proton with the FSR 4 flags set. Everything but the launcher and the
  # manifest is a symlink to the original tool. Proton finds its files from
  # the path it was started by, which stays the original one, since the
  # wrapper execs it by that path.
  withFsr4 =
    pkgs.runCommand "${ge.name}-fsr4"
      {
        outputs = [
          "out"
          "steamcompattool"
        ];
        __structuredAttrs = true;
      }
      ''
        echo "Use programs.steam.extraCompatPackages, not an environment." > "$out"

        mkdir "$steamcompattool"
        for f in ${src}/*; do
          ln -s "$f" "$steamcompattool/"
        done
        rm "$steamcompattool/proton" "$steamcompattool/compatibilitytool.vdf"

        # Its own internal name, so it never clashes with a plain GE-Proton,
        # and a display name that says which flavour this is.
        sed -E \
          -e 's|^(\s*)"([^"]+)"(\s*// Internal name)|\1"\2-FSR4"\3|' \
          -e 's|^(\s*"display_name"\s*")([^"]*)"|\1\2 (FSR 4)"|' \
          ${src}/compatibilitytool.vdf > "$steamcompattool/compatibilitytool.vdf"
        if ! grep -q -- '-FSR4"' "$steamcompattool/compatibilitytool.vdf"; then
          echo "steamix: could not find the internal name in ${src}/compatibilitytool.vdf" >&2
          exit 1
        fi

        cat > "$steamcompattool/proton" <<'EOF'
        #!${pkgs.runtimeShell}
        # Steamix (steamix.proton.fsr4): ask GE-Proton for FSR 4 in games that
        # ship FSR 3.1. Only set when unset, so a game's launch options win,
        # e.g. PROTON_FSR4_UPGRADE=0 to turn it off for that game.
        export PROTON_FSR4_UPGRADE="''${PROTON_FSR4_UPGRADE-${fsr4Value}}"
        ${lib.optionalString cfg.fsr4.indicator ''export PROTON_FSR4_INDICATOR="''${PROTON_FSR4_INDICATOR-1}"''}
        exec ${src}/proton "$@"
        EOF
        chmod +x "$steamcompattool/proton"
      '';
in
{
  options.steamix.proton = {
    ge = {
      enable = lib.mkEnableOption ''
        GE-Proton, a Proton build with extra game fixes and media codecs, as a
        Steam compatibility tool to pick per game
      '';

      package = lib.mkPackageOption pkgs "proton-ge-bin" {
        extraDescription = ''
          Anything with a `steamcompattool` output, as
          {option}`programs.steam.extraCompatPackages` expects. Also what the
          FSR 4 variant is built from.
        '';
      };
    };

    fsr4 = {
      enable = lib.mkEnableOption ''
        a "GE-Proton (FSR 4)" compatibility tool: GE-Proton with
        PROTON_FSR4_UPGRADE set, so it downloads and uses AMD's FSR 4 DLL in
        games that ship FSR 3.1. Needs an AMD RDNA 3 or RDNA 4 GPU. Choose it
        per game in Steam, or as Steam's default compatibility tool. Built
        from {option}`steamix.proton.ge.package`, and independent of
        {option}`steamix.proton.ge.enable`
      '';

      version = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "4.1.1";
        description = ''
          The FSR 4 DLL version to ask GE-Proton for. `null` takes the one
          GE-Proton currently considers the default.
        '';
      };

      indicator = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Draw AMD's FSR watermark in games, which shows whether FSR 4
          upscaling and frame generation are actually active.
        '';
      };
    };
  };

  config = lib.mkIf config.steamix.enable {
    programs.steam.extraCompatPackages =
      lib.optional cfg.ge.enable ge ++ lib.optional cfg.fsr4.enable withFsr4;
  };
}
