# A console system for bringing up a new device: log in on the screen or
# over SSH, get on Wi-Fi, look at the hardware. What the example SD images
# (nixosConfigurations.<device>) are built from; not for daily use.
#
# The `nixos` user logs in automatically on the console and has
# passwordless sudo, as on the NixOS installer. SSH needs a password set
# first: `passwd`.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # The device firmware (armada-firmware) has no licence.
  nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "armada-firmware";

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "input"
      "audio"
    ];
    initialHashedPassword = "";
  };
  security.sudo.wheelNeedsPassword = false;
  services.getty.autologinUser = "nixos";

  networking.networkmanager.enable = true;
  services.openssh.enable = true;

  environment.systemPackages = with pkgs; [
    alsa-utils
    evtest
    iw
    libdrm # modetest
    lshw
    pciutils
    usbutils
    vulkan-tools
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  system.stateVersion = config.system.nixos.release;
}
