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

  # What this SoC uses from linux-firmware: the Adreno 740's microcode and
  # the generic Adreno files beside it, the SM8550 directory, the video
  # firmware, the WCN7850's Wi-Fi 7 and Bluetooth. 53 MB of its 1.9 GB.
  linuxFirmware = pkgs.runCommand "linux-firmware-sm8550-${pkgs.linux-firmware.version}" { } ''
    cd ${pkgs.linux-firmware}/lib/firmware
    dest="$out/lib/firmware"
    mkdir -p "$dest/qcom" "$dest/ath12k"
    find qcom -maxdepth 1 \( -type f -o -type l \) -exec cp -L {} "$dest/qcom/" \;
    cp -rL qcom/sm8550 qcom/vpu "$dest/qcom/"
    cp -rL ath12k/WCN7850 "$dest/ath12k/"
    cp -rL qca "$dest/"
  '';
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
  # linux-firmware's. Of linux-firmware only this SoC's part: the whole of
  # it would be most of a minimal system's size. For other hardware (a USB
  # Wi-Fi adapter, say), set hardware.enableRedistributableFirmware.
  hardware.firmware = lib.mkMerge [
    (lib.mkBefore [ (package "armada-firmware") ])
    [ linuxFirmware ]
  ];
  hardware.enableRedistributableFirmware = lib.mkDefault false;
  hardware.wirelessRegulatoryDatabase = lib.mkDefault true;

  boot.loader.rocknix-abl.enable = lib.mkDefault true;
}
