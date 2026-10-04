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

  cases = heroicCases;
in
assert lib.all (x: x) cases;
pkgs.runCommand "steamix-options" { } ''
  echo "${toString (lib.length cases)} option checks passed" > "$out"
''
