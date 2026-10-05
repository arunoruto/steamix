# Boots a handheld SD image in QEMU's generic ARM machine (`virt`): not the
# device, whose Qualcomm hardware QEMU cannot emulate, but everything the
# bootloader hands over and everything after it. The kernel, initrd and
# command line come out of the image's own /KERNEL, as ROCKNIX ABL would
# take them; the image is the disk.
#
# Passes when the system reaches its login prompt with no failed units:
# the kernel boots, the initrd finds the root partition by label, and
# NixOS's stage 2 comes up on this kernel's config (a missing module shows
# up here as a failed service, as the firewall's did).
#
# Emulated (TCG) on any host, a few minutes; no KVM needed.
{
  pkgs,
  image,
  name,
}:
pkgs.runCommand "steamix-boot-${name}"
  {
    nativeBuildInputs = with pkgs; [
      qemu
      zstd
      util-linux
      mtools
      mkbootimg-osm0sis
      gzip
    ];
    requiredSystemFeatures = [ "big-parallel" ];
  }
  ''
    zstd -dq ${image}/sd-image/*.img.zst -o sd.img
    chmod u+w sd.img
    # Room for the root partition to grow into on first boot.
    truncate -s 8G sd.img

    # /KERNEL, from the first partition.
    eval "$(partx sd.img -o START,SECTORS --nr 1 --pairs)"
    dd if=sd.img of=fat.img bs=512 skip="$START" count="$SECTORS" status=none
    mcopy -i fat.img ::/KERNEL KERNEL
    mkdir boot
    unpackbootimg -i KERNEL -o boot > /dev/null
    # gzip(Image) with device trees after the stream: gzip warns about the
    # trailing data and exits 2.
    gzip -dc boot/KERNEL-kernel > Image || [ $? = 2 ]

    qemu-system-aarch64 \
      -machine virt,gic-version=3 -cpu max -smp "$NIX_BUILD_CORES" -m 4096 \
      -accel tcg,thread=multi -no-reboot -display none -monitor none \
      -kernel Image -initrd boot/KERNEL-ramdisk \
      -append "$(cat boot/KERNEL-cmdline) console=ttyAMA0" \
      -drive if=none,file=sd.img,format=raw,id=hd -device virtio-blk-pci,drive=hd \
      -nic user,model=virtio-net-pci \
      -serial file:console.log &
    qemu=$!

    result=timeout
    for _ in $(seq 360); do
      if grep -q "login:" console.log 2>/dev/null; then result=login; break; fi
      if grep -qE "Kernel panic|emergency mode|Timed out waiting for device" console.log 2>/dev/null; then
        result=failed; break
      fi
      kill -0 "$qemu" 2>/dev/null || { result=exited; break; }
      sleep 5
    done
    # Let late units settle before judging them.
    [ "$result" = login ] && sleep 30
    kill "$qemu" 2>/dev/null || true

    console() { sed 's/\x1b\[[0-9;]*[A-Za-z]//g' console.log | tr '\r' '\n'; }
    if [ "$result" != login ]; then
      console | tail -60
      echo "steamix: boot did not reach a login prompt ($result)"
      exit 1
    fi
    if console | grep -F "[FAILED]"; then
      echo "steamix: booted, but units failed"
      exit 1
    fi
    console | grep -E "Welcome to NixOS|Reached target Multi-User|login:" | head -5
    console > "$out"
  ''
