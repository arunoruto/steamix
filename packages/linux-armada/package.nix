# The Snapdragon handheld kernel from Armada OS: Linux from kernel.org with
# Armada's patch series (panels, the RSInput gamepad, LEDs, Adreno, audio),
# its out-of-tree device trees for every handheld it supports, and its kernel
# config.
#
# Built the nixpkgs way, so NixOS's own kernel requirements still apply: the
# base config is arm64's defconfig plus Armada's fragment (the kernel merges
# it as `make defconfig armada.config`), and nixpkgs' common config is then
# answered on top. Nothing else is turned into a module (`autoModules`), which
# keeps the build close to Armada's in size and time.
#
# Where nixpkgs' answers and Armada's disagree, `tests.armada-config`
# reports it: everything Armada builds in has to stay built in.
{
  lib,
  buildLinux,
  fetchurl,
  runCommand,
  callPackage,
  armadaSource,
  # kernelPatches, randstructSeed, features: forwarded to buildLinux, which
  # is how NixOS's boot.kernelPatches reaches the kernel (via `override`).
  ...
}@args:
let
  version = "7.2.6";

  armada = "${armadaSource}/packages/kernel";

  tarball = fetchurl {
    url = "mirror://kernel/linux/kernel/v7.x/linux-${version}.tar.xz";
    hash = "sha256-A5rvhPKwmUrto/T8/D0C7J16m7uQIOomTEP0Rshg9gY=";
  };

  # The source tree as Armada's build-kernel.sh prepares it, so that config
  # generation already sees the Kconfig symbols the patches add.
  src = runCommand "linux-${version}-armada-source" { } ''
    tar -xf ${tarball}
    cd linux-${version}

    . ${armada}/BASE.env
    if [ "$VERSION" != "${version}" ]; then
      echo "linux-armada: Armada expects Linux $VERSION, this package fetches ${version}" >&2
      exit 1
    fi

    sed 's/#.*//' ${armada}/patches/series | while read -r p _; do
      [ -n "$p" ] || continue
      echo "applying $p"
      patch -p1 --batch --forward -F0 --no-backup-if-mismatch --quiet < "${armada}/patches/$p"
    done

    # Board device trees are vendored whole and edited by their own patches;
    # the kernel only builds the ones its Makefile lists.
    dts=arch/arm64/boot/dts/qcom
    cp ${armada}/dts/*.dts ${armada}/dts/*.dtsi "$dts/"
    for p in ${armada}/dts/*.patch; do
      echo "applying $(basename "$p")"
      patch -p1 -F0 --no-backup-if-mismatch --quiet < "$p"
    done
    {
      echo
      echo "# Armada board DTBs"
      for f in ${armada}/dts/*.dts; do
        echo "dtb-\$(CONFIG_ARCH_QCOM) += $(basename "$f" .dts).dtb"
      done
    } >> "$dts/Makefile"

    # Kconfig cannot parse trailing comments on assignments.
    sed -E '/^[[:space:]]*CONFIG_[A-Z0-9_]+=/ s/[[:space:]]*#.*$//' \
      ${armada}/config/armada-kernel.config.overrides > arch/arm64/configs/armada.config

    cp -r . "$out"
  '';

  kernel = buildLinux (
    removeAttrs args [
      "lib"
      "buildLinux"
      "fetchurl"
      "runCommand"
      "callPackage"
      "armadaSource"
      "argsOverride"
    ]
    // {
      pname = "linux-armada";
      inherit version src;
      modDirVersion = version;

      defconfig = "defconfig armada.config";
      autoModules = false;
      # nixpkgs' common config names options whose parents this slimmer
      # config leaves off (PPP's, Xen's, PCMCIA's...); those are skipped
      # rather than failing the build.
      ignoreConfigErrors = true;

      structuredExtraConfig = with lib.kernel; {
        # The display has to be up before the root filesystem: as modules,
        # the screen stays dark from the bootloader on (Armada's own note).
        DRM_MSM = lib.mkForce yes;

        # Built in by Armada, overridden by nixpkgs' common config otherwise.
        BPF_JIT_ALWAYS_ON = lib.mkForce yes;
        NLS_UTF8 = lib.mkForce yes;
      };

      extraPassthru = {
        inherit armadaSource;
      };
      kernelTests.armada-config = callPackage ./config-test.nix { inherit kernel armada; };

      extraMeta = {
        description = "Linux kernel for Snapdragon handhelds, from Armada OS";
        homepage = "https://github.com/armada-os/armada";
        platforms = [ "aarch64-linux" ];
      };
    }
    // args.argsOverride or { }
  );
in
kernel
