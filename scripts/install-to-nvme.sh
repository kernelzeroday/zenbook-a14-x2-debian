#!/bin/bash
# Install the running live USB system onto the UX3407NA's internal NVMe with a LUKS2 root,
# keeping the Qualcomm firmware partitions p1-p11. Then add GNOME + Plymouth.
# Run as root on the live system booted from USB-A, with network access.
# DESTRUCTIVE: removes every partition from p12 up (Windows).
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
disk=/dev/nvme0n1
target=/mnt/target
firmware_labels=(ToolsFv LogFs EnterpriseFV ToolsFv_BACKUP UpdateCapsule NHLOS core_nhlos_a quantumsdk quantumfv catecontentfv logdump)

[ "$(id -u)" = 0 ] || { echo 'run as root' >&2; exit 1; }
grep -q UX3407NA /sys/class/dmi/id/product_name || { echo 'not a UX3407NA' >&2; exit 1; }
! findmnt -rn -o SOURCE | grep -q "^$disk" || { echo "$disk is in use" >&2; exit 1; }
for i in "${!firmware_labels[@]}"; do
    n=$((i + 1))
    label=$(lsblk -dno PARTLABEL "${disk}p$n")
    [ "$label" = "${firmware_labels[$i]}" ] || { echo "p$n is '$label', expected ${firmware_labels[$i]}; refusing" >&2; exit 1; }
done
p11_end=$(sgdisk -i 11 "$disk" | awk '/Last sector/ {print $3}')

echo "Backing up the GPT and p1-p11 to /root before changing anything"
sgdisk --backup=/root/nvme-gpt-before-debian.sgdisk "$disk"
dd if="$disk" bs=512 count=$((p11_end + 1)) status=none | gzip -1 > /root/nvme-p1-p11.img.gz
echo "Copy /root/nvme-gpt-before-debian.sgdisk and /root/nvme-p1-p11.img.gz off this USB stick."

sgdisk -p "$disk"
read -r -p "Delete every partition after p11 on $disk (Windows) and install Debian? Type ERASE: " answer
[ "$answer" = ERASE ] || { echo 'aborted'; exit 1; }

for n in $(sgdisk -p "$disk" | awk 'NR>1 && $1 ~ /^[0-9]+$/ && $1 > 11 {print $1}' | sort -rn); do sgdisk -d "$n" "$disk"; done
sgdisk -n 12:$((p11_end + 1)):+1G -t 12:EF00 -c 12:"Debian ESP" -n 13:0:0 -t 13:8309 -c 13:"Debian LUKS" "$disk"
partprobe "$disk"; udevadm settle
mkfs.vfat -F 32 -n DEBIANESP "${disk}p12"

modprobe dm_crypt   # the stock config lacked it; see config/kernel/a14-luks.config
echo "Choose the disk passphrase. You'll type it at every boot on the built-in US keyboard."
cryptsetup luksFormat --type luks2 --label debian-luks --pbkdf argon2id "${disk}p13"
cryptsetup open --tries 3 "${disk}p13" cryptroot
mkfs.ext4 -q -L debian-root /dev/mapper/cryptroot

mkdir -p "$target"
mount /dev/mapper/cryptroot "$target"
mkdir -p "$target/boot/efi"
mount "${disk}p12" "$target/boot/efi"
rsync -aHAXx --numeric-ids --exclude='/proc/*' --exclude='/sys/*' --exclude='/dev/*' --exclude='/run/*' \
    --exclude='/tmp/*' --exclude='/mnt/*' --exclude='/media/*' --exclude=/lost+found \
    --exclude='/var/cache/apt/archives/*.deb' / "$target/"
rsync -rt /boot/efi/ "$target/boot/efi/"

luks_uuid=$(blkid -s UUID -o value "${disk}p13")
esp_uuid=$(blkid -s UUID -o value "${disk}p12")
echo "cryptroot UUID=$luks_uuid none luks,discard" > "$target/etc/crypttab"
cat > "$target/etc/fstab" <<EOF
/dev/mapper/cryptroot	/	ext4	defaults,errors=remount-ro	0	1
UUID=$esp_uuid	/boot/efi	vfat	defaults,nosuid,nodev,noexec,relatime,fmask=0177,dmask=0077,shortname=mixed,errors=remount-ro	0	2
EOF
mkdir -p "$target/etc/cryptsetup-initramfs"
grep -qs '^CRYPTSETUP=y' "$target/etc/cryptsetup-initramfs/conf-hook" || echo 'CRYPTSETUP=y' >> "$target/etc/cryptsetup-initramfs/conf-hook"
install -m755 "$repo"/config/initramfs/hooks/* "$target/etc/initramfs-tools/hooks/"
sed -i '/^# ux3407na begin$/,/^# ux3407na end$/d' "$target/etc/initramfs-tools/modules"
{ echo '# ux3407na begin'; grep -vE '^(#|$)' "$repo/config/initramfs/modules"; echo '# ux3407na end'; } >> "$target/etc/initramfs-tools/modules"

for d in proc sys dev dev/pts run; do mount --bind "/$d" "$target/$d"; done
trap 'for d in run dev/pts dev sys proc; do umount "$target/$d" 2>/dev/null || true; done' EXIT
export DEBIAN_FRONTEND=noninteractive
chroot "$target" apt-get update
chroot "$target" apt-get install -y cryptsetup cryptsetup-initramfs plymouth plymouth-themes task-gnome-desktop
chroot "$target" tasksel install standard laptop english
chroot "$target" systemctl set-default graphical.target
# Live-image leftovers that fail on a laptop.
chroot "$target" systemctl disable debos-grow-rootfs.service qbootctl.service 2>/dev/null || true

read -r -p 'Username for the new system: ' user
chroot "$target" useradd -m -s /bin/bash -G sudo,adm,audio,video,render,plugdev,netdev,users "$user"
chroot "$target" passwd "$user"

release=$(uname -r)
chroot "$target" update-initramfs -u -k "$release"
cp "$target/boot/initrd.img-$release" "$target/boot/efi/asus-debian/initrd"
cp "$repo/config/boot/entries/asus-debian.conf" "$target/boot/efi/loader/entries/asus-debian.conf"
cp "$repo/config/boot/loader.conf" "$target/boot/efi/loader/loader.conf"
# kernel-install BLS entries from the live image point at the USB root.
find "$target/boot/efi/loader/entries" -name '*-*.conf' ! -name asus-debian.conf -delete
lsinitramfs "$target/boot/efi/asus-debian/initrd" | grep -qE 'dm-crypt.ko' || { echo 'dm-crypt missing from initramfs' >&2; exit 1; }
lsinitramfs "$target/boot/efi/asus-debian/initrd" | grep -qE 'panel-samsung-atna33xc20.ko' || { echo 'panel driver missing from initramfs' >&2; exit 1; }

efibootmgr -c -d "$disk" -p 12 -L Debian -l '\EFI\systemd\systemd-bootaa64.efi' || echo 'efibootmgr failed; use the Esc boot menu once'
sync
umount "$target/boot/efi"
for d in run dev/pts dev sys proc; do umount "$target/$d"; done
trap - EXIT
umount "$target"
cryptsetup close cryptroot
echo "Done. Power off, remove the USB stick, boot, unlock, log in as $user."
echo "The live image's 'debian' account was copied too: lock or remove it (passwd -l debian / deluser debian)."
