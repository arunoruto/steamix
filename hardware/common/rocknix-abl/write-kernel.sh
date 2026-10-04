# Write the Android boot image ROCKNIX ABL boots, /KERNEL, for a NixOS
# system: gzip(Image) with the device trees appended, the system's initrd,
# and a command line pointing at its init.
#
#   write-kernel <directory> <toplevel>
#
# The image replaces <directory>/KERNEL; the one it replaces, if different,
# is kept as KERNEL.BAK, the only fallback the bootloader offers.
#
# Set by the module in front of this script: mkbootimg, dtbs (array),
# mkbootimgArgs (array), cmdlineMax.

set -euo pipefail

dir=$1
top=$2

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

gzip -9n < "$top/kernel" > "$work/kernel.gz"
for dtb in "${dtbs[@]}"; do
  if [ ! -f "$top/dtbs/$dtb" ]; then
    echo "rocknix-abl: $top has no device tree $dtb" >&2
    exit 1
  fi
  cat "$top/dtbs/$dtb" >> "$work/kernel.gz"
done

cmdline="init=$top/init $(cat "$top/kernel-params")"
if [ "${#cmdline}" -gt "$cmdlineMax" ]; then
  echo "rocknix-abl: the kernel command line is ${#cmdline} bytes, the boot image holds $cmdlineMax:" >&2
  echo "  $cmdline" >&2
  exit 1
fi

"$mkbootimg" \
  --kernel "$work/kernel.gz" \
  --ramdisk "$top/initrd" \
  --cmdline "$cmdline" \
  "${mkbootimgArgs[@]}" \
  -o "$work/KERNEL"

mkdir -p "$dir"
if [ -f "$dir/KERNEL" ] && cmp -s "$work/KERNEL" "$dir/KERNEL"; then
  exit 0
fi
cp "$work/KERNEL" "$dir/KERNEL.tmp"
sync "$dir/KERNEL.tmp"
if [ -f "$dir/KERNEL" ]; then
  mv "$dir/KERNEL" "$dir/KERNEL.BAK"
fi
mv "$dir/KERNEL.tmp" "$dir/KERNEL"
sync "$dir"
