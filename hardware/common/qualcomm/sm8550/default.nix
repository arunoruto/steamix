# Snapdragon 8 Gen 2 (SM8550, QCS8550) handhelds, the way Armada OS supports
# them: its kernel, its device firmware, and booting through ROCKNIX ABL.
# Device modules (hardware/<vendor>/<model>) import this and add their
# device trees and quirks.
#
# Takes the packages from the Steamix overlay when it is applied, from this
# repository otherwise. armada-firmware is unfree.
{
  lib,
  pkgs,
  ...
}:
let
  steamixPackages = import ../../../../packages { inherit pkgs; };
  package = name: pkgs.${name} or steamixPackages.${name};
in
{
  imports = [ ../../rocknix-abl ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  boot.kernelPackages = lib.mkDefault (package "linuxPackages_armada");

  # Armada's hardware kernel arguments (bootc kargs.d): 32-bit userspace on
  # the cores that have it, strict device links so drivers probe in order,
  # and the bounce buffer size its devices need.
  boot.kernelParams = [
    "console=tty0"
    "allow_mismatched_32bit_el0"
    "fw_devlink.strict=1"
    "pcie_ports=compat"
    "swiotlb=8192"
  ];

  # The storage, display and USB drivers the initrd needs are built in; the
  # generic default list names modules for other SoCs this kernel lacks.
  boot.initrd.includeDefaultModules = false;

  # Device firmware first, so its newer Wi-Fi and Bluetooth files win over
  # linux-firmware's.
  hardware.firmware = lib.mkBefore [ (package "armada-firmware") ];
  hardware.enableRedistributableFirmware = lib.mkDefault true;

  boot.loader.rocknix-abl.enable = lib.mkDefault true;
}
