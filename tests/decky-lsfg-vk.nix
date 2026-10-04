# The Decky LSFG-VK plugin's backend on NixOS, without Decky or a VM: its
# installer and its settings validation are plain Python, driven here with
# a minimal stand-in for Decky's module and a scratch home.
#
# Guards the package's repairs: the plugin's own lsfg-vk build does not run
# on NixOS, so a plugin update that changes how it installs or validates
# would otherwise break silently. Checks that "Install lsfg-vk" puts every
# file in place, that the plugin then sees lsfg-vk as installed, that
# settings validation works (it runs lsfg-vk-cli), and that the CLI it
# installed into the home starts.
{ pkgs, plugin }:
let
  driver = pkgs.writeText "drive-decky-lsfg-vk.py" ''
    import sys

    sys.path[:0] = [sys.argv[1], sys.argv[2] + "/py_modules"]

    from lsfg_vk.installation import InstallationService
    from lsfg_vk.runtime_service import RuntimeService

    installer = InstallationService()
    result = installer.install()
    assert result["success"], result

    status = installer.check_installation()
    assert status["installed"], status

    runtime = RuntimeService()
    assert str(runtime.cli_path).startswith("/nix/store/"), runtime.cli_path
    runtime.validate_config_content((installer.config_dir / "conf.toml").read_text())

    print("installed, detected, and settings validate")
  '';
in
pkgs.runCommand "steamix-decky-lsfg-vk"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME" fake

    # What the plugin reads from Decky's module.
    cat > fake/decky.py <<EOF
    import logging
    logger = logging.getLogger("decky-lsfg-vk")
    DECKY_USER_HOME = "$HOME"
    DECKY_USER = "alice"
    EOF

    python3 ${driver} fake ${plugin}/decky-lsfg-vk
    "$HOME/.local/bin/lsfg-vk-cli" validate --config "$HOME/.config/lsfg-vk/conf.toml" > /dev/null

    echo ok > "$out"
  ''
