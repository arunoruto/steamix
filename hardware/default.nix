# Handheld hardware support, as NixOS modules: one directory per product
# under <vendor>/<model>, and what products are built from under common/
# (chips like common/qualcomm/sm8550, the bootloader). Every product
# directory with a default.nix becomes a module named <vendor>-<model>.
#
# Kept here while it takes shape; meant for nixos-hardware once it boots.
{ lib }:
let
  dirs = path: lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir path));
in
lib.listToAttrs (
  lib.concatMap (
    vendor:
    lib.concatMap (
      model:
      lib.optional (builtins.pathExists ./${vendor}/${model}/default.nix) {
        name = "${vendor}-${model}";
        value = ./${vendor}/${model};
      }
    ) (dirs ./${vendor})
  ) (lib.filter (d: d != "common") (dirs ./.))
)
// {
  qualcomm-sm8550 = ./common/qualcomm/sm8550;
  rocknix-abl = ./common/rocknix-abl;
  rocknix-abl-sd-image = ./common/rocknix-abl/sd-image.nix;
}
