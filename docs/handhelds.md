# Handhelds

Steamix carries NixOS support for Snapdragon handhelds in `hardware/`, built
on [Armada OS](https://github.com/armada-os/armada)'s work: its kernel
patches, device trees, kernel config and firmware, and the
[ROCKNIX ABL](https://github.com/ROCKNIX/abl) bootloader. It lives here while
it takes shape, and is meant for nixos-hardware once it boots. The plan
behind it is [ARM port: Retroid Pocket 6](./arm-port.md).

> **Status:** builds, and boots in an emulated ARM machine (QEMU, with the
> image's own `/KERNEL`); untested on hardware. The first device has not
> booted it yet.

## Devices

| Device | Module | SoC |
|--------|--------|-----|
| Retroid Pocket 6 | `nixosModules.retroid-pocket-6` | QCS8550 (Snapdragon 8 Gen 2) |

Armada supports about two dozen handhelds across four Snapdragon
generations, and the kernel here already builds all their device trees, so
adding one of them is mostly a `hardware/<vendor>/<model>/default.nix` that
names its device trees.

## Layout

```
hardware/
├── common/                       parts, not products
│   ├── qualcomm/sm8550/          Snapdragon 8 Gen 2: kernel, firmware, boot
│   ├── rocknix-abl/              boot.loader.rocknix-abl, and the SD image
│   └── bring-up.nix              the console system the example images use
└── retroid/pocket-6/             the product: its device trees and quirks
packages/
├── armada-source.nix     the pinned Armada revision everything comes from
├── linux-armada/         the kernel
├── armada-firmware/      device firmware (unfree)
└── rocknix-abl/          the bootloader and its flashing scripts
```

Every product, `hardware/<vendor>/<model>` with a `default.nix`, becomes a
NixOS module named `<vendor>-<model>`; nothing to register. Chips and other
shared parts live under `common/` and are imported by the products (the
SoC is also exported, as `qualcomm-sm8550`).

## How it boots

ROCKNIX ABL replaces the device's Android bootloader. It loads `/KERNEL` from
the first FAT partition of the SD card (or internal storage): an Android boot
image with the kernel, the device trees appended to it, the initrd and the
command line. `boot.loader.rocknix-abl` writes that file on every
`nixos-rebuild switch` or `boot`, keeping the previous one as `KERNEL.BAK`.
The bootloader has no menu of kernels, so that file is the only way back to
an older generation: if a new one does not boot, rename `KERNEL.BAK` to
`KERNEL` from another computer.

## The kernel

`linux-armada` is Linux 7.2.6 with Armada's 209 patches, built with nixpkgs'
`buildLinux`: arm64's defconfig plus Armada's config fragment, then nixpkgs'
common config on top, so NixOS's kernel requirements still hold. Its
`tests.armada-config` compares the result with Armada's fragment and fails
if anything Armada builds in became a module or was turned off. CI runs that
check, cross-compiled, on every change, which also catches a patch that
stops applying.

Building it natively under emulation takes hours. The x86_64 image (below)
cross-compiles it instead; to do the same in your own configuration:

```nix
{ inputs, pkgs, ... }:
{
  boot.kernelPackages = pkgs.linuxPackagesFor
    (import "${inputs.steamix}/packages" {
      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux.pkgsCross.aarch64-multiplatform;
    }).linux_armada;
}
```

## A bring-up image

```sh
nix build github:arunoruto/steamix#sd-image-retroid-pocket-6
```

builds an SD card image with a console system: the `nixos` user logs in on
the screen, `nmtui` gets it on Wi-Fi, and SSH works once `passwd` set a
password. The image's FAT partition also carries `rocknix_abl/`, the
bootloader and its flashing scripts.

Either machine works:

- **aarch64** (`packages.aarch64-linux`): built natively; the kernel comes
  from the [binary cache](./binary-cache.md), where CI puts it from GitHub's
  ARM runners.
- **x86_64** (`packages.x86_64-linux`): the kernel is cross-compiled, about
  an hour on a desktop. Everything else is still aarch64, mostly from
  cache.nixos.org; the rest builds under emulation, so the machine needs
  `boot.binfmt.emulatedSystems = [ "aarch64-linux" ];`.

The image contains `armada-firmware`, which has no licence: build it
yourself, and do not push it to a public cache.

Write it to a card (check the device name with `lsblk` first: `dd`
overwrites whatever it is given):

```sh
zstdcat result/sd-image/*.img.zst | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
```

## Steam

nixpkgs' `steam` wraps Valve's launcher, which only has an x86 bootstrap,
and does not evaluate on aarch64. `steam-arm` packages Valve's native ARM64
client instead, the one Valve's own ARM devices run (a public beta; Valve
has not released Steam for ARM Linux officially):

```nix
{ lib, pkgs, ... }:
{
  # steam-arm and its bootstrap are unfree.
  nixpkgs.config.allowUnfreePredicate =
    p: builtins.elem (lib.getName p) [ "steam-arm" "steam-arm-bootstrap" ];
  environment.systemPackages = [ pkgs.steam-arm ];
}
```

It works like nixpkgs' Steam. The store holds a bootstrap (the client's
updater from Valve's ARM64 manifest and Valve's ARM64 Steam Runtime, both
pinned by the SHA-256 Valve publishes, `packages/steam-arm/update.py` to
bump). The first launch copies it to `~/.local/share/Steam`, and the client
installs the rest of itself from Valve's servers (670 MB) and keeps itself
updated there. It runs in an FHS environment with the libraries the ARM64
client links against, started the way Armada starts it. It needs an
ARMv8.1 CPU with LSE atomics.

Status: the first-launch install is verified in an emulated ARM machine.
The client itself, its UI on the device's GPU, and games (ARM64 Proton,
FEX) are not yet. It is never cached: Valve publishes the client for
download, nothing grants redistributing it.

When Valve releases the ARM64 client officially, this is meant for
nixpkgs' `steam`.

## Size

The bring-up system is 1.9 GiB, the compressed image 690 MiB. Of
linux-firmware, only the SoC's part is installed (53 MB of 1.9 GB);
`hardware.enableRedistributableFirmware` brings back the rest, for a USB
Wi-Fi adapter say. With Plasma and gamescope on top, about 7 GiB.

For comparison, Armada's 2026-09-26 release uses 12.9 GB of its root
filesystem, compressed (btrfs, zstd), with Steam, Plasma, Waydroid and the
x86 graphics stack for FEX installed.

## Flashing the bootloader

This is the one step that can brick the device: there is no documented
recovery from a bad bootloader. Do it once, carefully, from the device's
Android:

1. Root Android, and copy `rocknix_abl/` from the SD card to the root of
   the internal storage.
2. Run `rocknix_abl/SM8550/backup_abl.sh` as root, and copy `abl_a.img` and
   `abl_b.img` somewhere off the device. They are the way back to stock.
3. Check you are in the folder for your SoC (`rocknix_abl/README` lists
   which device has which), then run `flash_abl.sh` as root.
4. Reboot holding Vol-. In the bootloader's menu, pick the device model,
   switch the boot mode to Linux, and start.

The bootloader is the same one Armada and ROCKNIX install, so a device that
already runs either of them can boot this image as it is.

## When the device arrives

1. Charge it and boot Android once, to know it works as shipped.
2. Build the image and write it to an SD card (above).
3. Back up and flash the bootloader (above). The backup is the step not to
   skip.
4. Reboot holding Vol-, pick Retroid Pocket 6 and Linux, boot from SD.
   There are two RP6 device trees, identical except that the "TOP-DPAD"
   one inverts both stick axes; if `evtest` shows the sticks inverted, pick
   the other model in the menu.
5. If the screen stays dark, try Armada's image on the same card first:
   if that boots, the difference is ours, not the hardware's.
6. Once NixOS is up: `nmtui` for Wi-Fi, `passwd`, then everything else over
   SSH. Collect `dmesg`, `lsmod` and `ls /sys/firmware/devicetree/base` for
   the next round.
