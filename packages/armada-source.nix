# Armada OS (https://github.com/armada-os/armada), Fedora for Snapdragon
# handhelds, pinned: the source of the kernel patches, device trees, kernel
# config, firmware and bootloader that Steamix's handheld support builds on.
# Bumping `rev` moves all of them together (and both hashes); the kernel
# version it expects is in packages/kernel/BASE.env and has to match
# linux-armada's.
#
# `kernelOnly` checks out just packages/kernel: the kernel's corresponding
# source, which the binary cache carries next to the kernel (GPL-2.0). The
# whole repository also holds firmware without a licence, which must not be
# redistributed.
{
  fetchFromGitHub,
  kernelOnly ? false,
}:
fetchFromGitHub (
  {
    owner = "armada-os";
    repo = "armada";
    rev = "f8f59dd2ee937b45be1f8d1f3ae7af9a33eb75e7";
  }
  // (
    if kernelOnly then
      {
        sparseCheckout = [ "packages/kernel" ];
        hash = "sha256-zklv/Y2ymea9+WmtlR/GIe7HsQErn+brVY31L30slRA=";
      }
    else
      {
        hash = "sha256-At16XP41zSYk2Q3vCRGLEvu/s/OtW6pWdmRvGfAClKw=";
      }
  )
)
