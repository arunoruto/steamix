# steamix.emulation's kiosk end to end: the machine boots into RetroArch,
# full screen in cage, as the configured user, with the configured cores
# and settings, and RetroArch comes back when it quits.
#
# Rendering is software (llvmpipe) in the VM; the screenshot is for a
# person looking at the test's output.
{ testLib }:
{
  name = "steamix-emulation";

  nodes.machine = {
    imports = [ testLib.baseNode ];

    steamix.user = "alice";
    steamix.emulation = {
      enable = true;
      kiosk.enable = true;
      retroarch.settings.menu_driver = "rgui";
    };
  };

  testScript = ''
    import shlex

    def retroarch_pid():
        return machine.succeed("pgrep -u alice -f -- '--appendconfig='").split()[0]

    machine.wait_for_unit("cage-tty1.service")
    machine.wait_until_succeeds("pgrep -u alice -f -- '--appendconfig='", timeout=120)

    with subtest("RetroArch runs full screen with the cores and settings"):
        pid = retroarch_pid()
        args = machine.succeed(f"tr '\\0' '\\n' < /proc/{pid}/cmdline")
        assert "--fullscreen" in args, args
        assert "-L" in args, args
        config = next(a.split("=", 1)[1] for a in args.splitlines() if a.startswith("--appendconfig="))
        settings = machine.succeed(f"cat {shlex.quote(config)}")
        assert 'menu_driver = "rgui"' in settings, settings
        assert 'rgui_browser_directory = "~/ROMs"' in settings, settings
        cores = machine.succeed(f"ls {shlex.quote(args.split('-L')[1].split()[0])}")
        for core in ["nestopia", "bsnes", "mgba", "pcsx_rearmed"]:
            assert core in cores, cores

    with subtest("its user can read controllers"):
        groups = machine.succeed("id -nG alice")
        assert "input" in groups.split(), groups

    machine.sleep(10)
    machine.screenshot("retroarch")

    with subtest("quitting RetroArch brings it back"):
        old = retroarch_pid()
        machine.succeed(f"kill {old}")
        machine.wait_until_succeeds(
            f"pid=$(pgrep -u alice -f -- '--appendconfig=' | head -1); [ -n \"$pid\" ] && [ \"$pid\" != {old} ]",
            timeout=60,
        )
  '';
}
