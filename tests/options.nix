# Evaluation-only checks for options simple enough that booting a VM would
# prove nothing more: each case evaluates a NixOS configuration with the
# module and asserts on the resulting config. Nothing is built, so the whole
# file costs seconds. Behaviour (sessions, daemons, switching) belongs in the
# VM tests next to it.
#
# A failing case fails evaluation of this derivation, with the case's name
# and what was found.
{ pkgs, testLib }:
let
  inherit (pkgs) lib;

  # A NixOS configuration with the module, Steam replaced by the stub (it is
  # unfree), and nothing booted.
  evalWith =
    module:
    (pkgs.nixos {
      imports = [
        ../modules/nixos
        module
      ];
      programs.steam.package = testLib.steam;
      users.users.alice.isNormalUser = true;
      boot.loader.grub.enable = false;
      fileSystems."/" = {
        device = "/dev/null";
        fsType = "ext4";
      };
      steamix.user = "alice";
      system.stateVersion = lib.trivial.release;
    }).config;

  systemPackageNames = config: map lib.getName config.environment.systemPackages;

  check =
    name: ok: found:
    lib.assertMsg ok "steamix options: ${name} (found: ${found})";

  heroicCases =
    let
      off = evalWith { steamix.enable = true; };
      on = evalWith {
        steamix.enable = true;
        steamix.heroic.enable = true;
      };
      steamixOff = evalWith { steamix.heroic.enable = true; };
      has = config: lib.elem "heroic" (systemPackageNames config);
    in
    [
      (check "heroic is not installed by default" (!has off) "heroic in systemPackages")
      (check "steamix.heroic.enable installs heroic" (has on) "heroic missing from systemPackages")
      (check "steamix.heroic.enable does nothing without steamix.enable" (
        !has steamixOff
      ) "heroic in systemPackages")
    ];

  losslessScalingCases =
    let
      # Stand-ins for lsfg-vk, so both config formats are checked on both
      # channels without building it (2.x is unfree).
      stub =
        version:
        pkgs.runCommand "lsfg-vk-${version}" {
          pname = "lsfg-vk";
          inherit version;
        } "mkdir $out";
      v1 = stub "1.0.0";
      v2 = stub "2.0.0";

      withLsfg =
        extra:
        evalWith (
          lib.recursiveUpdate {
            steamix.enable = true;
            steamix.losslessScaling.enable = true;
          } extra
        );

      # lsfg-vk entries only: the gamescope WSI layer is in the same lists.
      lsfgIn = pkgsList: map lib.getVersion (lib.filter (p: lib.getName p == "lsfg-vk") pkgsList);
      layers = config: lsfgIn config.hardware.graphics.extraPackages;
      layers32 = config: lsfgIn config.hardware.graphics.extraPackages32;
      # Parses the generated file back, so the checks are on what lsfg-vk reads.
      conf =
        config: builtins.fromTOML (builtins.readFile config.environment.etc."lsfg-vk/conf.toml".source);

      profile = {
        activeIn = [
          "1245620"
          "eldenring.exe"
        ];
        multiplier = 3;
        flowScale = 0.75;
      };

      off = evalWith { steamix.enable = true; };
      interactive = withLsfg { steamix.losslessScaling.package = v2; };
      declarativeV2 = withLsfg {
        steamix.losslessScaling = {
          package = v2;
          dll = "/games/Lossless Scaling";
          profiles.elden-ring = profile;
        };
      };
      declarativeV1 = withLsfg {
        steamix.losslessScaling = {
          package = v1;
          profiles.elden-ring = profile // {
            hdrMode = true;
          };
        };
      };
      with32 = withLsfg {
        steamix.losslessScaling = {
          package = v2;
          support32Bit = {
            enable = true;
            package = v2;
          };
        };
      };
      uiWithProfiles = withLsfg {
        steamix.losslessScaling = {
          package = v2;
          ui.enable = true;
          profiles.elden-ring = profile;
        };
      };

      c2 = conf declarativeV2;
      c1 = conf declarativeV1;
    in
    [
      (check "the layer is not installed by default" (!lib.elem "2.0.0" (layers off)) "lsfg-vk layer")
      (check "enable installs the layer" (lib.elem "2.0.0" (layers interactive)) "no lsfg-vk layer")
      (check "the 32-bit layer is opt-in" (
        layers32 interactive == [ ] && layers32 with32 == [ "2.0.0" ]
      ) (builtins.toJSON (layers32 with32)))
      (check "no profiles leaves the config interactive" (
        !(interactive.environment.etc ? "lsfg-vk/conf.toml")
        && !(interactive.environment.sessionVariables ? LSFGVK_CONFIG)
      ) "a managed config")
      (check "2.x: version, global and the profile" (
        c2.version == 2
        &&
          c2.global == {
            allow_fp16 = true;
            dll = "/games/Lossless Scaling";
          }
        &&
          c2.profile == [
            {
              name = "elden-ring";
              active_in = [
                "1245620"
                "eldenring.exe"
              ];
              multiplier = 3;
              flow_scale = 0.75;
              performance_mode = false;
              pacing_mode = "vsync";
            }
          ]
      ) (builtins.toJSON c2))
      (check "2.x: sessions read it through LSFGVK_CONFIG" (
        declarativeV2.environment.sessionVariables.LSFGVK_CONFIG == "/etc/lsfg-vk/conf.toml"
      ) "no LSFGVK_CONFIG")
      (check "1.x: one [[game]] per executable, 1.x keys only" (
        c1.version == 1
        &&
          map (g: g.exe) c1.game == [
            "1245620"
            "eldenring.exe"
          ]
        && lib.all (
          g: g.multiplier == 3 && g.flow_scale == 0.75 && g.hdr_mode && !(g ? pacing_mode) && !(g ? name)
        ) c1.game
      ) (builtins.toJSON c1))
      (check "1.x: sessions read it through LSFG_CONFIG" (
        declarativeV1.environment.sessionVariables.LSFG_CONFIG == "/etc/lsfg-vk/conf.toml"
        && !(declarativeV1.environment.sessionVariables ? LSFGVK_CONFIG)
      ) "wrong variable")
      (check "1.x warns that Steam App IDs never match" (lib.any (
        w: lib.hasInfix "1245620" w && lib.hasInfix "never apply" w
      ) declarativeV1.warnings) "no warning")
      (check "2.x does not warn about Steam App IDs" (
        !lib.any (w: lib.hasInfix "never apply" w) declarativeV2.warnings
      ) "a warning")
      (check "the UI with profiles warns that it cannot change them" (lib.any (
        w: lib.hasInfix "losslessScaling.ui.enable" w
      ) uiWithProfiles.warnings) "no warning")
    ];

  cases = heroicCases ++ losslessScalingCases;
in
assert lib.all (x: x) cases;
pkgs.runCommand "steamix-options" { } ''
  echo "${toString (lib.length cases)} option checks passed" > "$out"
''
