# An SD card image ROCKNIX ABL boots: an MBR card (Android refuses GPT SD
# cards) with a bootable FAT32 partition first, holding /KERNEL and the rocknix_abl/
# flashing folder, then the ext4 root. Build it with
# `config.system.build.sdImage`; the root partition grows to the card on
# first boot.
#
# The FAT partition stays mounted at /boot/firmware, so switching to a new
# generation rewrites /KERNEL there.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  rocknix-abl = pkgs.rocknix-abl or (import ../../../packages { inherit pkgs; }).rocknix-abl;
in
{
  imports = [
    "${modulesPath}/installer/sd-card/sd-image.nix"
    ./.
  ];

  boot.loader.rocknix-abl = {
    enable = true;
    mountPoint = "/boot/firmware";
  };

  # sd-image mounts the firmware partition only on demand.
  fileSystems."/boot/firmware".options = lib.mkForce [
    "fmask=0022"
    "dmask=0022"
  ];

  # Set by sd-image for generic boards; it pulls in initrd modules for SoCs
  # a handheld kernel does not build.
  hardware.enableAllHardware = lib.mkForce false;

  sdImage = {
    # Two boot images (KERNEL and KERNEL.BAK), each a kernel plus initrd.
    firmwareSize = 512;
    populateFirmwareCommands = ''
      ${config.system.build.rocknixAblWriteKernel} firmware ${config.system.build.toplevel}
      cp -r ${rocknix-abl}/rocknix_abl firmware/
    '';
    populateRootCommands = "";
    # The FAT partition as ROCKNIX and Armada make it: FAT32 (LBA) and
    # marked bootable, where sd-image marks the root partition for U-Boot.
    postBuildCommands = ''
      sfdisk --no-reread --no-tell-kernel --part-type "$img" 1 c
      sfdisk --no-reread --no-tell-kernel --activate "$img" 1
    '';
  };
}
