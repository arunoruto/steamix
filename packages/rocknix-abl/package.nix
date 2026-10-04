# ROCKNIX ABL, the replacement Android bootloader that boots Linux on
# Snapdragon handhelds, as Armada OS ships it: a `rocknix_abl/` folder to
# copy to the device's Android storage, with one directory per SoC holding
# the signed bootloader and the scripts that back up, flash and restore it
# (run as root from Android). See rocknix_abl/README.
#
# Flashing the wrong SoC's bootloader can brick a device, so the build only
# succeeds when every payload matches the size and SHA-256 Armada approved
# for its release.
{
  lib,
  stdenvNoCC,
  armadaSource,
}:
let
  socs = [
    "SM8250"
    "SM8550"
    "SM8650"
    "SM8750"
  ];
in
stdenvNoCC.mkDerivation {
  pname = "rocknix-abl";
  version = "1.1.8";

  src = "${armadaSource}/abl";

  __structuredAttrs = true;
  strictDeps = true;

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    . ./release.env
    if [ "$ARMADA_ABL_VERSION" != "$version" ]; then
      echo "rocknix-abl: Armada ships $ARMADA_ABL_VERSION, this package says $version" >&2
      exit 1
    fi

    dest="$out/rocknix_abl"
    mkdir -p "$dest"
    cp README "$dest/README"

    for soc in ${lib.escapeShellArgs socs}; do
      payload="abl_signed-$soc.elf"
      read -r size hash < <(awk -v v="$version" -v s="$soc" '$1 == v && $2 == s { print $3, $4 }' releases.tsv)
      if [ -z "$hash" ] \
        || [ "$(stat -c %s "$payload")" != "$size" ] \
        || [ "$(sha256sum "$payload" | cut -d ' ' -f 1)" != "$hash" ]; then
        echo "rocknix-abl: $payload does not match the approved $version release" >&2
        exit 1
      fi

      mkdir "$dest/$soc"
      cp "$payload" "$dest/$soc/"
      echo "$hash  $payload" > "$dest/$soc/$payload.sha256"
      for s in flash_abl backup_abl restore_backup_abl; do
        sed "s/%DEVICE%/$soc/g" "$s.sh.template" > "$dest/$soc/$s.sh"
        chmod 0755 "$dest/$soc/$s.sh"
      done
    done

    runHook postInstall
  '';

  meta = {
    description = "Bootloader that boots Linux on Snapdragon handhelds, with Armada's flashing scripts";
    homepage = "https://github.com/ROCKNIX/abl";
    # GPL-2.0 per ROCKNIX, but only signed binaries are published.
    license = lib.licenses.gpl2Only;
    sourceProvenance = [ lib.sourceTypes.binaryFirmware ];
    platforms = lib.platforms.all;
  };
}
