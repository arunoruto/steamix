# Valve's native ARM64 Steam client, the one Valve's ARM devices run
# (public beta; Valve has not released Steam for ARM Linux officially). The
# counterpart of nixpkgs' `steam` for aarch64-linux, which wraps Valve's
# x86 launcher and has no ARM64 bootstrap to wrap.
#
# Works like nixpkgs' Steam: the first launch puts a bootstrap into
# ~/.local/share/Steam (./bootstrap.nix: the client's updater and Valve's
# ARM64 runtime), the client installs the rest of itself from Valve's
# servers and keeps itself updated there. It runs in an FHS environment
# with the libraries Valve's ARM64 client links against, and is started as
# Armada OS starts it (its launch-steam).
#
# Needs an ARMv8.1 CPU with LSE atomics, which the client requires since
# April 2026.
{
  lib,
  callPackage,
  buildFHSEnv,
  writeShellScript,
  extraPkgs ? pkgs: [ ],
  extraArgs ? "",
}:
let
  bootstrap = callPackage ./bootstrap.nix { };

  launcher = writeShellScript "steam-arm" ''
    set -euo pipefail

    steam_root="''${STEAM_ROOT:-$HOME/.local/share/Steam}"
    steam_arm_dir="$steam_root/steamrtarm64"

    # First launch: the bootstrap, which the client completes and updates.
    if [ ! -x "$steam_arm_dir/steam" ]; then
      mkdir -p "$steam_root"
      cp -r --no-preserve=ownership ${bootstrap}/share/steam-arm/Steam/. "$steam_root/"
      chmod -R u+w "$steam_root"
    fi

    # Where Steam and the games it runs look for it.
    mkdir -p "$HOME/.steam"
    for link in steam root; do
      [ -e "$HOME/.steam/$link" ] || ln -sfn "$steam_root" "$HOME/.steam/$link"
    done
    [ -e "$HOME/.steam/sdkarm64" ] || ln -sfn "$steam_root/linuxarm64" "$HOME/.steam/sdkarm64"

    export LD_LIBRARY_PATH="$steam_arm_dir:$steam_root/lib/aarch64-linux-gnu''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    if [ -d "$steam_root/steam-runtime-steamrt-arm64/bin" ]; then
      export PATH="$steam_root/steam-runtime-steamrt-arm64/bin:$PATH"
    fi
    # Steam restores these for compatibility tools, which otherwise start
    # with no PATH.
    export SYSTEM_PATH="$PATH"
    export SYSTEM_LD_LIBRARY_PATH="$LD_LIBRARY_PATH"

    # What Valve's steam.sh does for its x86 clients (it has no ARM64
    # path): Steam exits with 42 when it wants to be started again, after
    # updating itself, the first launch included.
    cd "$steam_arm_dir"
    while true; do
      status=0
      ./steam ${extraArgs} "$@" || status=$?
      if [ "$status" != 42 ]; then
        exit "$status"
      fi
      echo "steam-arm: restarting Steam by request" >&2
    done
  '';
in
buildFHSEnv {
  pname = "steam-arm";
  inherit (bootstrap) version;

  includeClosures = true;

  # As nixpkgs' Steam (the Steam Runtime's distro assumptions), plus what
  # Valve's ARM64 client links against from the host, read from the ELF
  # files of an installed client. 64-bit only: there is no 32-bit half on
  # ARM.
  targetPkgs =
    pkgs:
    with pkgs;
    [
      bash
      coreutils
      file
      lsb-release
      pciutils
      glibc.bin
      usbutils
      xdg-utils
      xz
      zenity
      # taskset: steamwebhelper.sh pins the web helper to cores with it
      util-linux

      glibc
      libxcrypt
      stdenv.cc.cc.lib
      libGL
      libdrm
      libgbm
      udev
      libudev0-shim
      libva
      vulkan-loader
      networkmanager
      libcap

      libx11
      libxcb
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxinerama
      libxi
      libxrandr
      libxrender
      libxtst
      libice
      libsm
      glib
      gtk2
      gdk-pixbuf
      fontconfig
      freetype
      dbus
      libpulseaudio
      pipewire
      openal
      libsndfile
      libasyncns
      systemd
      zlib
      zstd
      openssl
      libssh2
      brotli
      SDL2

      # steamwebhelper (Chromium), which the client installs on first launch
      alsa-lib
      atk
      at-spi2-atk
      at-spi2-core
      bzip2
      cairo
      cups
      expat
      libvdpau
      libxkbcommon
      nspr
      nss
      pango

      # crashes on startup if it can't find libx11 locale files
      (pkgs.runCommand "xorg-locale" { } ''
        mkdir -p $out
        ln -s ${libx11}/share $out/share
      '')
    ]
    ++ extraPkgs pkgs;

  profile = ''
    # As nixpkgs' Steam: no host GIO modules in Steam's GTK, joysticks
    # found without udev events (unreliable in containers), XIM for input
    # methods, and the system's graphics drivers.
    unset GIO_EXTRA_MODULES
    export SDL_JOYSTICK_DISABLE_UDEV=1
    export GTK_IM_MODULE='xim'
    export LIBGL_DRIVERS_PATH=/run/opengl-driver/lib/dri
    export __EGL_VENDOR_LIBRARY_DIRS=/run/opengl-driver/share/glvnd/egl_vendor.d
    export LIBVA_DRIVERS_PATH=/run/opengl-driver/lib/dri
  '';

  # Steam expects a real /sbin/ldconfig (a symlink loops in nested
  # containers).
  extraBuildCommands = ''
    cp -f $out/usr/{bin,sbin}/ldconfig
  '';

  runScript = launcher;

  passthru = {
    inherit bootstrap;
    inherit (bootstrap) updateScript;
  };

  meta = bootstrap.meta // {
    description = "Valve's native ARM64 Steam client (public beta), in an FHS environment";
    mainProgram = "steam-arm";
  };
}
