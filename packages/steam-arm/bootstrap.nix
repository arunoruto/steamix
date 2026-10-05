# What a first launch of steam-arm copies into ~/.local/share/Steam: the
# ARM64 client's seed package (its own updater, which downloads and
# installs the rest of the client from Valve on that first launch, as x86
# Steam's bootstrap does) and Valve's ARM64 Steam Runtime. Laid out as
# Armada OS's Steam bootstrap lays them out.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  file,
}:
let
  sources = lib.importJSON ./sources.json;
in
stdenvNoCC.mkDerivation {
  pname = "steam-arm-bootstrap";
  inherit (sources.client) version;

  srcs = [
    (fetchurl {
      url = "https://client-update.steamstatic.com/${sources.client.seed.file}";
      sha256 = sources.client.seed.sha256;
    })
    (fetchurl {
      url = "https://repo.steampowered.com/steamrt3c/images/${sources.runtime.version}/steam-runtime-steamrt-arm64.tar.xz";
      sha256 = sources.runtime.sha256;
    })
  ];

  __structuredAttrs = true;
  strictDeps = true;

  nativeBuildInputs = [
    unzip
    file
  ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  # Valve's binaries, run as they are inside steam-arm's FHS environment.
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    steam="$out/share/steam-arm/Steam"
    mkdir -p "$steam"
    seed=''${srcs[0]}
    runtime=''${srcs[1]}

    unzip -q "$seed" -d "$steam"
    # Some entries are stored with Windows path separators: files go where
    # the separators say, the (empty) directory entries go away.
    (
      cd "$steam"
      find . -maxdepth 1 -name '*\\*' ! -type d -print0 | while IFS= read -r -d "" f; do
        target=$(printf '%s' "''${f#./}" | tr '\\' /)
        mkdir -p "$(dirname "$target")"
        mv -f "$f" "$target"
      done
      find . -maxdepth 1 -name '*\\*' -type d -empty -delete
    )

    # The archive keeps no permissions: make programs and scripts runnable.
    find "$steam" -type f -print0 | while IFS= read -r -d "" f; do
      case "$(file -b "$f")" in
        *"interpreter /lib/ld-linux"* | "POSIX shell script"* | "Python script"*)
          chmod +x "$f"
          ;;
      esac
    done

    tar -xJf "$runtime" -C "$steam"
    ibus=$(find "$steam/steam-runtime-steamrt-arm64" -path '*/files/lib/aarch64-linux-gnu/libibus-1.0.so.5.*' -type f | sort | tail -n1)
    mkdir -p "$steam/lib/aarch64-linux-gnu"
    ln -s "../../''${ibus#"$steam/"}" "$steam/lib/aarch64-linux-gnu/libibus-1.0.so.5"

    mkdir -p "$steam/package"
    echo ${sources.client.channel} > "$steam/package/beta"

    test -x "$steam/steamrtarm64/steam"

    runHook postInstall
  '';

  passthru.updateScript = ./update.py;

  meta = {
    description = "Seed of Valve's ARM64 Steam client and its runtime";
    homepage = "https://store.steampowered.com/";
    # Valve publishes these for download from its servers; nothing grants
    # redistributing them, so they are not cached.
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "aarch64-linux" ];
  };
}
