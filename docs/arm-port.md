# ARM port: Retroid Pocket 6

The plan for running NixOS with Steamix on a Retroid Pocket 6 (12 GB / 256 GB):
a Steam machine on a Snapdragon handheld, the way
[Armada OS](https://github.com/armada-os/armada) does it on Fedora, as the
centrepiece of a NixCon 2027 talk. Written 2026-10-04 from reading Armada
(`main`, f8f59dd), ROCKNIX (`next`, a7a96a5) and nixpkgs (`nixos-unstable`,
c59305ba). Nobody has run NixOS on these handhelds yet.

## The device

| | |
|---|---|
| SoC | QCS8550 (Snapdragon 8 Gen 2, SM8550 family), Adreno 740 |
| Device tree | `qcs8550-retroidpocket-rp6.dts` (and `-rp6-top-dpad`), out of tree, an Odin 2 derivative (`qcs8550-ayn-common.dtsi`) |
| Display | 1080x1920 portrait AMOLED, rotated (`rotation = <270>`): gamescope `--force-orientation left` |
| Controller | RSInput MCU on uart15 (`rsinput` driver), shows up as "AYN Odin2 Gamepad" |
| Audio | sound card "AYN-Odin2", UCM `AYN/Odin2` |
| Fan | `pwm-fan`, kernel thermal trips |
| Suspend | broken on ROCKNIX ("fake suspend"); Armada defaults to s2idle |

## How it boots

The stock Qualcomm bootloader (ABL) only boots Android. Armada and ROCKNIX
replace it with [ROCKNIX ABL](https://github.com/ROCKNIX/abl), flashed with
`dd` from rooted Android onto `abl_a` and `abl_b`. Its source is private; what
it does is known from how both distributions use it:

- it boots from SD, internal storage or USB, chosen in a menu (hold Vol- at
  power-on), where the device model is also picked;
- it loads `/KERNEL` from the first FAT partition: an **Android boot image,
  header v0**, holding gzip(Image) with every DTB appended, an initramfs and
  a command line of at most 512 bytes. Armada's mkbootimg arguments:
  `--base 0x10000000 --pagesize 2048 --kernel_offset 0x8000 --ramdisk_offset 0x06000000 --tags_offset 0x100 --header_version 0`;
- there is no boot menu of kernels, so rollback is a kept `KERNEL.BAK`;
- it also has an EFI path (Armada disables `/EFI` so it falls through to
  `/KERNEL`). Whether systemd-boot would run there is unknown, and worth
  trying once the basic path works, because it would give NixOS its
  generation menu back.

## Architecture

Two layers, kept apart so each can go upstream on its own:

- **Device support** (kernel, device tree, firmware, boot image, SD image):
  not Steamix-specific. In Steamix's `hardware/` to start with (see
  [Handhelds](./handhelds.md)), aimed at nixos-hardware later.
- **Steam on ARM** (Valve's ARM64 client, FEX for x86 games, the Gaming Mode
  session on aarch64): Steamix, with the generic parts (FEX module, client
  package) aimed at nixpkgs.

Builds are native aarch64, not cross-compiled, so everything Hydra builds
comes from cache.nixos.org. The kernel, the one big uncached build, is built
on an aarch64 machine (a GitHub `ubuntu-24.04-arm` runner, free for public
repositories, pushing to Cachix) or cross-compiled for speed; small uncached
derivations build locally through `boot.binfmt.emulatedSystems`. GitHub's ARM
runners have no KVM, so aarch64 CI evaluates and builds but does not boot VM
tests; the device itself is the test bench.

## Phase 0: before the device arrives

Done (2026-10-05), see [Handhelds](./handhelds.md): the kernel, the boot
image writer, the SD image and the firmware are in `hardware/` and
`packages/`, with the kernel config and the boot image checked in CI. The
image was compared with Armada's 2026-09-26 release: same partition layout
and flags, same boot image header (all but the patch-level date), and the
RP6 device tree decompiles identical. Left: booting it.

1. **Kernel.** `buildLinux` with Linux 7.2.6 and Armada's patch series
   (209 patches: the RP6 panel driver, RSInput gamepad, LEDs, touchscreen,
   haptics, Adreno 740 fixes). The RP6 device trees copied into
   `arch/arm64/boot/dts/qcom` in `postPatch`. Config: arm64 defconfig plus
   Armada's overrides as `structuredExtraConfig`; built in: `DRM_MSM` (as a
   module the screen stays black after the bootloader hands it over), the
   panel, `LEDS_QCOM_LPG`, `QCOM_PMIC_GLINK`, compressed firmware loading;
   4K pages (FEX needs them).
2. **Boot image.** A `boot.loader.external` installer that writes
   `/boot/KERNEL` on every `nixos-rebuild`: mkbootimg (nixpkgs
   `android-tools`) with the arguments above, gzip(Image) with both RP6 DTBs
   appended, the NixOS initrd, and `init=<toplevel>/init` plus
   `boot.kernelParams` under 512 bytes. The previous one is kept as
   `KERNEL.BAK`. mobile-nixos's boot image builder is prior art.
3. **SD image.** nixpkgs' `sd-image` module: MBR (Android refuses GPT cards),
   a FAT partition first with `KERNEL` and `rocknix_abl/`, then the ext4
   root.
4. **Verify the format without the device.** Download an Armada release,
   unpack its `KERNEL` with `unpackbootimg`, and compare header, offsets,
   DTB order and command line with ours.
5. **Firmware, provisionally.** linux-firmware carries the redistributable
   parts (`qcom/a740_sqe.fw`, `qcom/gmu_gen70200.bin`,
   `qcom/sm8550/a740_zap.mbn`, Wi-Fi and Bluetooth). The ADSP and CDSP blobs
   (battery, charging, audio) are OEM files without a licence: an unfree
   derivation, never pushed to a public cache, eventually extracted from
   your own device rather than taken from Armada.

## Phase 1: bring-up

1. **Back up first.** Root Android, run Armada's `backup_abl.sh`, and keep
   `abl_a.img` and `abl_b.img` off the device. Flashing the wrong SoC's ABL,
   or an interrupted `dd`, leaves the device unbootable, and no recovery
   procedure (EDL / firehose) is documented.
2. **Flash ROCKNIX ABL** for SM8550, then boot **Armada from SD**: proves the
   bootloader and hardware, and gives a reference for `dmesg`, loaded
   modules and firmware.
3. **Boot NixOS from SD**: serial-free bring-up means the panel has to work
   first; then input, Wi-Fi and SSH, after which everything else is remote.
4. **Extract the firmware** from Android's partitions and package it.

## Phase 2: a handheld

Gamescope on Turnip (Mesa 26.2 has Adreno 740), audio through the `AYN/Odin2`
UCM profile, the controller through `rsinput` and InputPlumber, the
orientation, fan and power handling, suspend disabled until s2idle is
tested. Steamix's session, switching, Decky (built from source, so native on
aarch64, where Armada runs Decky's x86 binary under FEX) and BoilR carry over.

## Phase 3: Steam

nixpkgs' Steam is x86-only (`programs.steam` needs the 32-bit package set),
so Steam on ARM is a separate package, modelled on Armada's bootstrap:

- **Valve's ARM64 client**: the `steam_client_steamdeck_publicbeta_linuxarm64`
  manifest from `client-update.steamstatic.com` lists every package with a
  SHA-256, so each becomes a `fetchurl`, pinned by manifest version, with an
  update script. Plus Valve's `steam-runtime-steamrt-arm64` tarball, whose
  hash Valve publishes. Unfree, never in a public cache.
- **A seed, not an install**: Steam updates its own tree in
  `~/.local/share/Steam`, so the store holds the seeded client and the first
  launch copies it into place; launched with Armada's environment
  (`steamrtarm64/steam`, its `LD_LIBRARY_PATH`) and Steamix's Gaming Mode
  flags.
- Steamix's Gaming Mode session on aarch64 starts that instead of
  `programs.steam`.

## Phase 4: x86 games

- **Windows games** run on Valve's own ARM64 Proton (`proton_11-arm64`,
  `proton-experimental-arm64`), served by Steam, with Wine ARM64EC and
  Valve's FEX inside. It expects an x86 graphics stack at the hardcoded path
  `/usr/share/guestos/fex-mesa`: Armada overlays FEX's Arch Linux root
  filesystem with an x86_64 and i686 Turnip build there.
- **Native x86 Linux games** run through the system FEX: nixpkgs has `fex`
  (2608, with thunks) but no NixOS module yet; the draft PR
  [nixpkgs#379544](https://github.com/NixOS/nixpkgs/pull/379544) adds one with
  binfmt registration. Needed on top: FEX's config, FEXServer with
  erofs-fuse, the pinned root filesystem, and the guestos overlay as a
  systemd mount.
- Armada also carries kernel patches emulating unaligned atomics, which some
  x86 games need under FEX.

## Phase 5: the Steamix experience

Lossless Scaling (lsfg-vk has community ARM ports), SteamOS Manager with
Valve's Steam Frame patches (it identifies devices by DMI, which ARM boards do
not have), handheld controls, the settings GUI. Then the demo: the same
Steamix module on a PC and on a Snapdragon handheld.

## Timeline

| When | What |
|------|------|
| Oct - Nov 2026 | Phase 0, and bring-up as soon as the device is there |
| Dec 2026 - Jan 2027 | A handheld: graphics, input, audio, Steamix's session |
| Feb - Mar 2027 | Steam's ARM64 client |
| Spring 2027 | NixCon call for talks: submit with what runs then |
| Apr - Jun 2027 | x86 games through FEX and ARM64 Proton |
| Summer 2027 | Polish, Steamix features, the talk |

## Risks

- **Bricking** while flashing the bootloader, with no documented recovery.
- **A closed bootloader**: ROCKNIX ABL cannot be rebuilt or audited; its
  behaviour is inferred.
- **Firmware without a licence**: the OEM ADSP and CDSP blobs.
- **Patch maintenance**: 209 out-of-tree kernel patches, few upstreamed.
- **Valve's ARM64 client is a public beta**: no stable URL, versions can be
  withdrawn.
- **Undocumented pieces of Valve's ARM stack**: what its FEX tooling and
  runtime expect from the host beyond the guestos path.
