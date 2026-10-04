# The /KERNEL writer of boot.loader.rocknix-abl, run against a stand-in
# system: the boot image unpacks to Armada's geometry, the kernel is
# gzip(Image) with the device trees appended in order, the command line
# points at the system's init, and a second system moves the first image to
# KERNEL.BAK. Also that an over-long command line and a missing device tree
# are refused rather than written.
{ pkgs }:
let
  inherit (pkgs) lib;

  writeKernel =
    (pkgs.nixos {
      imports = [ ../hardware/common/rocknix-abl ];
      boot.loader.rocknix-abl = {
        enable = true;
        dtbs = [
          "qcom/board-a.dtb"
          "qcom/board-b.dtb"
        ];
      };
      fileSystems."/".device = "/dev/null";
      system.stateVersion = lib.trivial.release;
    }).config.system.build.rocknixAblWriteKernel;
in
pkgs.runCommand "steamix-rocknix-abl"
  {
    nativeBuildInputs = [
      pkgs.mkbootimg-osm0sis
      pkgs.gzip
    ];
  }
  ''
    # A stand-in toplevel: what the writer reads from a NixOS system.
    system() {
      mkdir -p "$1/dtbs/qcom"
      echo "Image of $1" > "$1/kernel"
      echo "initrd of $1" > "$1/initrd"
      echo "dtb A" > "$1/dtbs/qcom/board-a.dtb"
      echo "dtb B" > "$1/dtbs/qcom/board-b.dtb"
      echo -n "$2" > "$1/kernel-params"
    }
    system "$PWD/one" "console=tty0 loglevel=4"
    system "$PWD/two" "console=tty0"

    ${writeKernel} boot "$PWD/one"
    [ -f boot/KERNEL ] && [ ! -e boot/KERNEL.BAK ]

    mkdir unpacked
    unpackbootimg -i boot/KERNEL -o unpacked > unpack.log
    cat unpack.log
    check() { grep -qx -- "$1" "unpacked/KERNEL-$2" || { echo "$2: want '$1', got '$(cat "unpacked/KERNEL-$2")'"; exit 1; }; }
    check "init=$PWD/one/init console=tty0 loglevel=4" cmdline
    check 0x10000000 base
    check 2048 pagesize
    check 0x00008000 kernel_offset
    check 0x06000000 ramdisk_offset
    check 0x00000100 tags_offset
    check 0 header_version
    check 12.0.0 os_version
    check 2026-10 os_patch_level

    cmp unpacked/KERNEL-ramdisk one/initrd
    # gzip stops at the end of its stream; what follows are the device trees.
    { gzip -9n < one/kernel; cat one/dtbs/qcom/board-a.dtb one/dtbs/qcom/board-b.dtb; } > expected-kernel
    cmp unpacked/KERNEL-kernel expected-kernel

    # Same system again: nothing changes, the backup is not overwritten.
    first=$(sha256sum < boot/KERNEL)
    ${writeKernel} boot "$PWD/one"
    [ ! -e boot/KERNEL.BAK ]

    # A new system: the previous image becomes the backup.
    ${writeKernel} boot "$PWD/two"
    [ "$(sha256sum < boot/KERNEL.BAK)" = "$first" ]
    [ "$(sha256sum < boot/KERNEL)" != "$first" ]

    # Refused, and the images left alone.
    system "$PWD/long" "$(printf 'x%.0s' $(seq 600))"
    if ${writeKernel} boot "$PWD/long" 2> long.log; then echo "accepted a 600-byte command line"; exit 1; fi
    grep -q "bytes, the boot image holds 512" long.log
    rm "$PWD/one/dtbs/qcom/board-b.dtb"
    if ${writeKernel} boot "$PWD/one" 2> dtb.log; then echo "accepted a missing device tree"; exit 1; fi
    grep -q "has no device tree qcom/board-b.dtb" dtb.log
    [ "$(sha256sum < boot/KERNEL.BAK)" = "$first" ]

    echo ok > "$out"
  ''
