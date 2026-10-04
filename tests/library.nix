# steamix.library.boilr end to end: BoilR runs inside the Gaming Mode
# session before Steam starts, adds the games another launcher installed to
# Steam's library, keeps shortcuts it did not create, does not duplicate
# anything on the next login, and gets its SteamGridDB key from a file at
# runtime.
#
# The other launcher is a fake Heroic install: the file Heroic keeps its
# installed Epic games in, with one game. Steam is the stub from ./lib.nix,
# so what is checked is Steam's library file itself, which the real client
# would read on start.
{ testLib }:
let
  steamUserId = "12345678";
in
{
  name = "steamix-library";

  nodes.machine =
    { config, pkgs, ... }:
    let
      home = config.users.users.alice.home;

      # Reads Steam's binary shortcuts.vdf and prints its entries as JSON.
      dumpShortcuts =
        pkgs.writers.writePython3Bin "dump-shortcuts" { libraries = [ pkgs.python3Packages.vdf ]; }
          ''
            import json
            import sys
            import vdf

            with open(sys.argv[1], "rb") as f:
                data = vdf.binary_load(f)
            entries = data.get("shortcuts", {}).values()
            print(json.dumps([
                {
                    "name": e.get("AppName") or e.get("appname"),
                    "exe": e.get("Exe") or e.get("exe"),
                    "options": e.get("LaunchOptions"),
                    "devkit": e.get("DevkitGameID"),
                }
                for e in entries
            ]))
          '';

      # A library that already holds one shortcut added by hand.
      seededShortcuts =
        pkgs.runCommand "shortcuts.vdf"
          {
            nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.vdf ])) ];
          }
          ''
            python3 - <<'EOF'
            import vdf
            shortcuts = {"shortcuts": {"0": {
                "appid": 1234567,
                "AppName": "Added By Hand",
                "Exe": "\"/run/current-system/sw/bin/true\"",
                "StartDir": "\"/\"",
                "LaunchOptions": "",
                "tags": {},
            }}}
            with open("${placeholder "out"}", "wb") as f:
                vdf.binary_dump(shortcuts, f)
            EOF
          '';

      # What Heroic writes for an installed Epic game.
      heroicInstalled = pkgs.writeText "installed.json" (
        builtins.toJSON {
          SteamixTestGame = {
            app_name = "SteamixTestGame";
            title = "Steamix Test Game";
            is_dlc = false;
            install_path = "${home}/Games/Heroic/SteamixTestGame";
            executable = "Game.exe";
            launch_parameters = "";
          };
        }
      );
    in
    {
      imports = [ testLib.baseNode ];

      steamix = {
        enable = true;
        user = "alice";
        library.boilr = {
          enable = true;
          steamGridDbKeyFile = "/etc/steamgriddb-key";
          # No network in the VM: keep the key, skip the downloads.
          settings.steamgrid_db.enabled = false;
        };
      };

      environment.etc."steamgriddb-key" = {
        text = "0123abcdTESTKEY\n";
        mode = "0400";
        user = "alice";
      };

      environment.systemPackages = [ dumpShortcuts ];

      # Steam's and Heroic's state as a real login would find it. Created by
      # alice's own tmpfiles instance, so every directory is hers.
      systemd.user.tmpfiles.users.alice.rules = [
        "d %h/.local/share/Steam/userdata/${steamUserId}/config 0755 - - -"
        "L+ %h/.steam/steam - - - - %h/.local/share/Steam"
        "C %h/.local/share/Steam/userdata/${steamUserId}/config/shortcuts.vdf - - - - ${seededShortcuts}"
        "z %h/.local/share/Steam/userdata/${steamUserId}/config/shortcuts.vdf 0644 - - -"
        "L+ %h/.config/heroic/legendaryConfig/legendary/installed.json - - - - ${heroicInstalled}"
      ];
    };

  testScript =
    { nodes, ... }:
    let
      dir = testLib.stateDir;
      home = nodes.machine.users.users.alice.home;
      shortcuts = "${home}/.local/share/Steam/userdata/${steamUserId}/config/shortcuts.vdf";
    in
    ''
      import json

      def starts():
          return int(machine.succeed("cat ${dir}/steam-starts 2>/dev/null || echo 0").strip())

      def library():
          return json.loads(machine.succeed("dump-shortcuts ${shortcuts}"))

      machine.start()
      machine.wait_for_unit("greetd.service")
      machine.wait_until_succeeds("test \"$(cat ${dir}/steam-starts 2>/dev/null)\" -ge 1", timeout=180)

      with subtest("BoilR runs in the session, before Steam starts"):
          lines = machine.succeed("journalctl -b -t steamix-session --no-pager -o cat").splitlines()
          sync = next(i for i, l in enumerate(lines) if "syncing other launchers' games" in l)
          steam = next(i for i, l in enumerate(lines) if "gamescope stub: running" in l)
          assert sync < steam, "BoilR ran after Steam started"
          assert not any("did not finish cleanly" in l for l in lines), "\n".join(lines)

      with subtest("the Heroic game is in Steam's library, launched through Heroic"):
          entries = library()
          game = [e for e in entries if e["name"] == "Steamix Test Game"]
          assert len(game) == 1, entries
          assert game[0]["exe"].strip('"') == "heroic", game
          assert game[0]["options"] == "heroic://launch/SteamixTestGame", game
          assert (game[0]["devkit"] or "").startswith("boilr"), game

      with subtest("a shortcut added by hand is kept"):
          assert [e["name"] for e in library()].count("Added By Hand") == 1, library()

      with subtest("the config is generated, with the key read from its file"):
          conf = machine.succeed("cat ${home}/.config/boilr/config.toml")
          assert 'auth_key = "0123abcdTESTKEY"' in conf, conf
          assert "@steamix-steamgriddb-key@" not in conf, conf
          assert "optimize_for_big_picture = true" in conf, conf
          mode = machine.succeed("stat -c %a ${home}/.config/boilr/config.toml").strip()
          assert mode == "600", f"config.toml is {mode}, holds a key"

      with subtest("the next login syncs again without duplicating"):
          machine.succeed("pkill -KILL -u alice -x gamescope")
          machine.wait_until_succeeds("test \"$(cat ${dir}/steam-starts)\" -ge 2", timeout=180)
          names = [e["name"] for e in library()]
          assert names.count("Steamix Test Game") == 1, names
          assert names.count("Added By Hand") == 1, names
    '';
}
