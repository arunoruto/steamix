# Booting NixOS through ROCKNIX ABL, the replacement Android bootloader on
# Snapdragon handhelds (see packages/rocknix-abl for flashing it).
#
# The bootloader loads /KERNEL from the first FAT partition of the boot
# device: an Android boot image (header version 0) holding gzip(Image) with
# the device trees appended, an initramfs, and a command line of at most 512
# bytes. It picks the device tree from its qcom,msm-id and qcom,board-id and,
# where devices share those, the model chosen in its menu. There is no menu of kernels, so NixOS generations are not
# selectable at boot: every switch rewrites /KERNEL and keeps the previous
# one as KERNEL.BAK, to rename back by hand if a generation does not boot.
#
# The geometry is Armada OS's (system_files/usr/lib/armada/bootimg-args).
# nixpkgs' mkbootimg (osm0sis's) writes the same image as the AOSP one
# Armada uses, except for the unused second-stage load address, which the
# bootloader ignores when there is no second stage.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.boot.loader.rocknix-abl;

  writeKernel = pkgs.writeShellScript "rocknix-abl-write-kernel" ''
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.diffutils
        pkgs.gzip
      ]
    }
    mkbootimg=${lib.getExe' cfg.mkbootimgPackage "mkbootimg"}
    dtbs=(${lib.escapeShellArgs cfg.dtbs})
    mkbootimgArgs=(${lib.escapeShellArgs cfg.mkbootimgArgs})
    cmdlineMax=${toString cfg.cmdlineMax}

    ${builtins.readFile ./write-kernel.sh}
  '';
in
{
  options.boot.loader.rocknix-abl = {
    enable = lib.mkEnableOption "booting through ROCKNIX ABL, which loads /KERNEL from a FAT partition";

    mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/boot";
      description = "Where the FAT partition ROCKNIX ABL boots from is mounted.";
    };

    dtbs = lib.mkOption {
      type = lib.types.nonEmptyListOf lib.types.str;
      example = [ "qcom/qcs8550-retroidpocket-rp6.dtb" ];
      description = ''
        Device trees to append to the kernel, relative to the system's
        device tree directory ({option}`hardware.deviceTree`). The
        bootloader picks the one matching the device.
      '';
    };

    mkbootimgPackage = lib.mkPackageOption pkgs "mkbootimg-osm0sis" { };

    mkbootimgArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "--base"
        "0x10000000"
        "--pagesize"
        "2048"
        "--kernel_offset"
        "0x00008000"
        "--ramdisk_offset"
        "0x06000000"
        "--tags_offset"
        "0x00000100"
        "--header_version"
        "0"
        "--os_version"
        "12.0.0"
        "--os_patch_level"
        "2026-10"
      ];
      description = ''
        The boot image geometry, as mkbootimg arguments. A wrong value here
        makes /KERNEL unbootable.
      '';
    };

    cmdlineMax = lib.mkOption {
      type = lib.types.ints.positive;
      default = 512;
      description = ''
        The longest kernel command line the boot image may carry. Header
        version 0 has 512 bytes, and an extra 1024 the bootloader may not
        read.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.deviceTree.enable = true;

    boot.loader.external = {
      enable = true;
      installHook = pkgs.writeShellScript "install-rocknix-abl" ''
        exec ${writeKernel} ${lib.escapeShellArg cfg.mountPoint} "$1"
      '';
    };

    system.build.rocknixAblWriteKernel = writeKernel;
  };
}
