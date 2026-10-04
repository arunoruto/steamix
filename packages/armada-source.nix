# Armada OS (https://github.com/armada-os/armada), Fedora for Snapdragon
# handhelds, pinned: the source of the kernel patches, device trees, kernel
# config, firmware and bootloader that Steamix's handheld support builds on.
# Bumping `rev` moves all of them together; the kernel version it expects is
# in packages/kernel/BASE.env and has to match linux-armada's.
{ fetchFromGitHub }:
fetchFromGitHub {
  owner = "armada-os";
  repo = "armada";
  rev = "f8f59dd2ee937b45be1f8d1f3ae7af9a33eb75e7";
  hash = "sha256-At16XP41zSYk2Q3vCRGLEvu/s/OtW6pWdmRvGfAClKw=";
}
