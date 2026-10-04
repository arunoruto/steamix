# The device firmware Armada OS carries for its Snapdragon handhelds, beyond
# linux-firmware: each device's audio DSP (ADSP) and compute DSP (CDSP)
# images with their service maps, speaker amplifier tuning, audio
# topologies, and newer Wi-Fi and Bluetooth firmware.
#
# The DSP images come from the devices' Android systems and have no licence,
# so this package is unfree and must not be pushed to a public cache.
{
  lib,
  stdenvNoCC,
  armadaSource,
}:
stdenvNoCC.mkDerivation {
  pname = "armada-firmware";
  version = "0-unstable-2026-10-04";

  src = "${armadaSource}/system_files/usr/lib/firmware";

  __structuredAttrs = true;
  strictDeps = true;

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/firmware"
    cp -r . "$out/lib/firmware/"
    runHook postInstall
  '';

  meta = {
    description = "Device firmware for Snapdragon handhelds, from Armada OS";
    homepage = "https://github.com/armada-os/armada";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryFirmware ];
    platforms = lib.platforms.linux;
  };
}
