#!/bin/sh
# Turn a qcom-deb-images trixie disk image into a bootable UX3407NA live image.
# Operates only on image files, never physical disks. Run inside the builder container.
#   env: BASE_IMAGE (qcom-deb-images disk-sdcard.img), IMAGE (output), KERNEL_SRC,
#        FIRMWARE (dir with qcom/glymur/ASUSTeK/UX3407NA/*), ATH_TOOLS (qcom-ath-board-update checkout)
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
base=${BASE_IMAGE:-/work/qcom-deb-images/disk-sdcard.img}
image=${IMAGE:-/work/asus-debian.img}
src=${KERNEL_SRC:-/work/asus-linux74}
firmware=${FIRMWARE:-/firmware}
ath_tools=${ATH_TOOLS:-/work/qcom-ath-board-update}
board=qcom/glymur/ASUSTeK/UX3407NA
root=/mnt/asus-image
# qcom-deb-images layout: 512 MiB ESP at 4 MiB, rootfs after it.
esp_offset=4194304 esp_size=536870912 root_offset=545259520 root_size=8044658176

for f in qcadsp8480.mbn adsp_dtbs.elf qccdsp8480.mbn cdsp_dtbs.elf qcdxkmsuc8480.mbn bdwlan_qcc2072_1p0_ncm820A.elf; do
    [ -f "$firmware/$board/$f" ] || { echo "missing firmware $board/$f" >&2; exit 1; }
done
[ ! -e "$image" ] || { echo "$image exists" >&2; exit 1; }
cp --reflink=auto --sparse=always "$base" "$image"

mkdir -p "$root"
cleanup() {
    rc=$?
    trap - EXIT INT TERM
    set +e
    for point in "$root/sys" "$root/proc" "$root/dev" "$root/boot/efi" "$root"; do
        if mountpoint -q "$point"; then umount "$point" || rc=1; fi
    done
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mount -o loop,offset=$root_offset,sizelimit=$root_size "$image" "$root"
mount -o loop,offset=$esp_offset,sizelimit=$esp_size "$image" "$root/boot/efi"
mount --bind /dev "$root/dev"
mount -t proc proc "$root/proc"
mount -t sysfs -o ro sysfs "$root/sys"

# Board firmware (extracted from your own Windows install) + initramfs hooks/modules.
mkdir -p "$root/usr/lib/firmware/updates/$board"
cp -a "$firmware/$board/." "$root/usr/lib/firmware/updates/$board/"
chown -R 0:0 "$root/usr/lib/firmware/updates/$board"
install -m755 "$repo"/config/initramfs/hooks/* "$root/etc/initramfs-tools/hooks/"
sed -i '/^# ux3407na begin$/,/^# ux3407na end$/d' "$root/etc/initramfs-tools/modules"
{ echo '# ux3407na begin'; grep -vE '^(#|$)' "$repo/config/initramfs/modules"; echo '# ux3407na end'; } >> "$root/etc/initramfs-tools/modules"

# Wi-Fi board data.
mkdir -p "$root/opt/asus-wifi-tools"
cp -a "$ath_tools/." "$root/opt/asus-wifi-tools/"
"$repo/scripts/wifi-offline-calibrate.sh" "$root"

# Kernel package from scripts/build-kernel.sh.
release=$(make -s -C "$src" ARCH=arm64 kernelrelease)
package=$(find "$(dirname "$src")" -maxdepth 1 -name "linux-image-${release}_*.deb" ! -name '*-dbg*')
[ "$(printf '%s\n' "$package" | grep -c .)" -eq 1 ]
cp "$package" "$root/tmp/linux-image.deb"
chroot "$root" dpkg -i /tmp/linux-image.deb
rm "$root/tmp/linux-image.deb"
chroot "$root" update-initramfs -u -k "$release"

# Boot files: unwrapped EFI kernel + DTB (patched kernel tree, sound node disabled).
mkdir -p "$root/boot/efi/asus-debian" "$root/boot/efi/loader/entries"
cp "$src/arch/arm64/boot/vmlinuz.efi" "$root/boot/efi/asus-debian/linux.efi"
"$repo/scripts/dtb-fixups.sh" "$src/arch/arm64/boot/dts/qcom/glymur-asus-zenbook-a14-ux3407na.dtb" \
    "$root/boot/efi/asus-debian/asus-ux3407na.dtb" --disable-sound
cp "$root/boot/initrd.img-$release" "$root/boot/efi/asus-debian/initrd"
rootfs_uuid=$(blkid -s UUID -o value "$(findmnt -n -o SOURCE "$root")")
sed "s/<rootfs-uuid>/$rootfs_uuid/" "$repo/config/boot/entries/asus-debian-usb.conf" \
    > "$root/boot/efi/loader/entries/asus-debian.conf"
cp "$repo/config/boot/loader.conf" "$root/boot/efi/loader/loader.conf"
sync
echo "Prepared $image (kernel $release)"
