# Evaluation-only checks for options simple enough that booting a VM would
# prove nothing more: each case evaluates a NixOS configuration with the
# module and asserts on the resulting config. Nothing is built during
# evaluation (no import-from-derivation); the few checks on generated files
# run when the derivation builds. The whole file costs seconds. Behaviour (sessions, daemons, switching) belongs in the
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
      # The value the TOML file is generated from (pkgs.formats.toml keeps it
      # on the derivation: as is on nixos-unstable, as JSON on 26.05).
      # Reading the file itself would make evaluation build it, which
      # `nix flake check --no-build` cannot do.
      conf =
        config:
        let
          value = config.environment.etc."lsfg-vk/conf.toml".source.value;
        in
        if builtins.isString value then builtins.fromJSON value else value;

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
      ui =
        version:
        pkgs.runCommand "lsfg-vk-ui-${version}" {
          pname = "lsfg-vk-ui";
          inherit version;
        } "mkdir $out";
      uiMatching = withLsfg {
        steamix.losslessScaling = {
          package = v2;
          ui = {
            enable = true;
            package = ui "2.0.0";
          };
        };
      };
      uiMismatched = withLsfg {
        steamix.losslessScaling = {
          package = v2;
          ui = {
            enable = true;
            package = ui "1.0.0";
          };
        };
      };
      uiWithProfiles = withLsfg {
        steamix.losslessScaling = {
          package = v2;
          ui = {
            enable = true;
            package = ui "2.0.0";
          };
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
      (check "ui.package is what gets installed" (lib.elem "2.0.0" (
        map lib.getVersion (
          lib.filter (p: lib.getName p == "lsfg-vk-ui") uiMatching.environment.systemPackages
        )
      )) "no lsfg-vk-ui 2.0.0")
      (check "a UI on another major version than the layer warns" (
        lib.any (w: lib.hasInfix "ui.package is lsfg-vk-ui" w) uiMismatched.warnings
        && !lib.any (w: lib.hasInfix "ui.package is lsfg-vk-ui" w) uiMatching.warnings
      ) "wrong warnings")
      (check "the UI with profiles warns that it cannot change them" (lib.any (
        w: lib.hasInfix "losslessScaling.ui.enable" w
      ) uiWithProfiles.warnings) "no warning")
    ];

  # A stand-in for proton-ge-bin's steamcompattool: the real manifest layout,
  # and a `proton` that reports how it was started instead of running Wine.
  geStub =
    pkgs.runCommand "proton-ge-bin-GE-Proton-stub"
      {
        outputs = [
          "out"
          "steamcompattool"
        ];
      }
      ''
        echo stub > "$out"
        mkdir "$steamcompattool"
        cat > "$steamcompattool/compatibilitytool.vdf" <<'EOF'
        "compatibilitytools"
        {
          "compat_tools"
          {
            "GE-Proton" // Internal name of this tool
            {
              "install_path" "."
              "display_name" "GE-Proton"
              "from_oslist"  "windows"
              "to_oslist"    "linux"
            }
          }
        }
        EOF
        echo '"manifest" { "commandline" "/proton %verb%" }' > "$steamcompattool/toolmanifest.vdf"
        cat > "$steamcompattool/proton" <<'EOF'
        #!${pkgs.runtimeShell}
        echo "argv0=$0"
        echo "args=$*"
        echo "PROTON_FSR4_UPGRADE=''${PROTON_FSR4_UPGRADE-unset}"
        echo "PROTON_FSR4_INDICATOR=''${PROTON_FSR4_INDICATOR-unset}"
        EOF
        chmod +x "$steamcompattool/proton"
      '';

  protonCases =
    let
      withProton = extra: evalWith (lib.recursiveUpdate { steamix.enable = true; } extra);
      compat = config: config.programs.steam.extraCompatPackages;
      names = config: map (p: p.name) (compat config);

      off = withProton { };
      geOnly = withProton {
        steamix.proton.ge = {
          enable = true;
          package = geStub;
        };
      };
      fsr4 = withProton {
        steamix.proton = {
          ge.package = geStub;
          fsr4.enable = true;
        };
      };
      both = withProton {
        steamix.proton = {
          ge = {
            enable = true;
            package = geStub;
          };
          fsr4.enable = true;
        };
      };
    in
    [
      (check "GE-Proton is not installed by default" (names off == [ ]) (builtins.toJSON (names off)))
      (check "ge.enable installs GE-Proton as it is" (names geOnly == [ geStub.name ]) (
        builtins.toJSON (names geOnly)
      ))
      (check "fsr4.enable adds only the FSR 4 variant" (names fsr4 == [ "${geStub.name}-fsr4" ]) (
        builtins.toJSON (names fsr4)
      ))
      (check "with ge.enable too, both are there" (
        names both == [
          geStub.name
          "${geStub.name}-fsr4"
        ]
      ) (builtins.toJSON (names both)))
    ];

  # What the FSR 4 tool's files say. Checked when the derivation builds:
  # reading them during evaluation would make evaluation build them.
  protonFiles =
    let
      tool =
        module:
        (lib.head
          (evalWith (
            lib.recursiveUpdate {
              steamix.enable = true;
              steamix.proton = {
                ge.package = geStub;
                fsr4.enable = true;
              };
            } module
          )).programs.steam.extraCompatPackages
        ).steamcompattool;
      fsr4 = tool { };
      pinned = tool {
        steamix.proton.fsr4 = {
          version = "4.1.1";
          indicator = true;
        };
      };
    in
    ''
      # the wrapper asks for the default FSR 4 unless told otherwise
      grep -qF 'PROTON_FSR4_UPGRADE-1}' ${fsr4}/proton
      ! grep -qF PROTON_FSR4_INDICATOR ${fsr4}/proton
      # version and indicator reach the wrapper
      grep -qF 'PROTON_FSR4_UPGRADE-4.1.1}' ${pinned}/proton
      grep -qF 'PROTON_FSR4_INDICATOR-1}' ${pinned}/proton
      # it is GE-Proton (FSR 4) under its own internal name
      grep -qF '"display_name" "GE-Proton (FSR 4)"' ${fsr4}/compatibilitytool.vdf
      grep -qF '"GE-Proton-FSR4" // Internal name' ${fsr4}/compatibilitytool.vdf
    '';

  # Run the wrapped launcher against the stub: the flag arrives, the real
  # launcher is started by its own path (Proton finds its files from that),
  # arguments pass through, and a game's own setting wins.
  wrapperRuns =
    let
      eval = evalWith {
        steamix.enable = true;
        steamix.proton = {
          ge.package = geStub;
          fsr4.enable = true;
        };
      };
      tool = (lib.head eval.programs.steam.extraCompatPackages).steamcompattool;
    in
    ''
      ran=$(${tool}/proton waitforexitandrun game.exe)
      echo "$ran"
      grep -qx "argv0=${geStub.steamcompattool}/proton" <<<"$ran"
      grep -qx "args=waitforexitandrun game.exe" <<<"$ran"
      grep -qx "PROTON_FSR4_UPGRADE=1" <<<"$ran"
      grep -qx "PROTON_FSR4_INDICATOR=unset" <<<"$ran"
      ran=$(PROTON_FSR4_UPGRADE=0 ${tool}/proton run game.exe)
      grep -qx "PROTON_FSR4_UPGRADE=0" <<<"$ran"
    '';

  losslessDeckyCases =
    let
      v2 = pkgs.runCommand "lsfg-vk-2.0.0" {
        pname = "lsfg-vk";
        version = "2.0.0";
      } "mkdir $out";
      pluginStub = pkgs.runCommand "decky-lsfg-vk-stub" { } "mkdir $out";

      withDecky =
        extra:
        evalWith (
          lib.recursiveUpdate {
            steamix = {
              enable = true;
              decky-loader.enable = true;
              losslessScaling = {
                enable = true;
                package = v2;
                deckyPlugin.package = pluginStub;
              };
            };
          } extra
        );

      plugins = config: map (p: p.name) config.steamix.decky-loader.plugins;
      hasLayer = config: lib.any (p: lib.getName p == "lsfg-vk") config.hardware.graphics.extraPackages;
      warned = config: lib.any (w: lib.hasInfix "Decky LSFG-VK plugin was not added" w) config.warnings;

      asSteamUser = withDecky { steamix.decky-loader.user = "alice"; };
      asDeckyUser = withDecky { };
      withProfiles = withDecky {
        steamix.decky-loader.user = "alice";
        steamix.losslessScaling.profiles.game.activeIn = [ "game" ];
      };
      forcedWithProfiles = withDecky {
        steamix.decky-loader.user = "alice";
        steamix.losslessScaling = {
          deckyPlugin.enable = true;
          profiles.game.activeIn = [ "game" ];
        };
      };
    in
    [
      (check "Decky as the Steam user: the plugin manages lsfg-vk" (
        plugins asSteamUser == [ pluginStub.name ] && !hasLayer asSteamUser
      ) (builtins.toJSON (plugins asSteamUser)))
      (check "Decky as its own user: Steamix's layer, no plugin, and a warning why" (
        plugins asDeckyUser == [ ] && hasLayer asDeckyUser && warned asDeckyUser
      ) (builtins.toJSON (plugins asDeckyUser)))
      (check "declarative profiles keep Steamix's layer and leave the plugin out" (
        plugins withProfiles == [ ] && hasLayer withProfiles && !warned withProfiles
      ) (builtins.toJSON (plugins withProfiles)))
      (check "forcing the plugin with profiles is an assertion" (lib.any (
        a: !a.assertion && lib.hasInfix "deckyPlugin.enable and profiles" a.message
      ) forcedWithProfiles.assertions) "no failing assertion")
    ];

  cases = heroicCases ++ losslessScalingCases ++ losslessDeckyCases ++ protonCases;
in
assert lib.all (x: x) cases;
pkgs.runCommand "steamix-options" { } ''
  ${protonFiles}
  ${wrapperRuns}
  echo "${toString (lib.length cases)} option checks passed, and the FSR 4 wrapper runs" > "$out"
''
