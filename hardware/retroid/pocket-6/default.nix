# Retroid Pocket 6: Snapdragon 8 Gen 2 (QCS8550), a 1080x1920 AMOLED panel
# mounted rotated (its device tree says so, and the console and compositors
# follow), the RSInput gamepad.
#
# Two device trees, the "TOP-DPAD" one inverting both stick axes; they
# share their board IDs, so both go into /KERNEL and the model picked in
# ROCKNIX ABL's menu (hold Vol- at power-on) decides.
{ lib, ... }:
{
  imports = [ ../../common/qualcomm/sm8550 ];

  hardware.deviceTree.name = lib.mkDefault "qcom/qcs8550-retroidpocket-rp6.dtb";

  boot.loader.rocknix-abl.dtbs = [
    "qcom/qcs8550-retroidpocket-rp6.dtb"
    "qcom/qcs8550-retroidpocket-rp6-top-dpad.dtb"
  ];

  # The gamepad, a microcontroller on a serial line. Loaded early, as
  # Armada does, so its calibration is in place before anything reads it.
  boot.kernelModules = [ "rsinput" ];
}
