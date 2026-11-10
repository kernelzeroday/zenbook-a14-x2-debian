#!/bin/sh
# Install a kernel built by build-kernel.sh *next to* the working one and arm a one-shot boot.
# Run as root:  install-kernel-esp.sh KERNELRELEASE [DEB_DIR] [ENTRY_NAME]
#
# - installs linux-image-KERNELRELEASE*.deb (initramfs-tools builds the initrd)
# - refuses to touch the ESP if the initrd lacks LUKS / display / storage pieces
# - copies kernel, initrd and the UX3407NA DTB (speaker sound node disabled) to /ENTRY_NAME/
# - writes loader/entries/ENTRY_NAME.conf but does NOT change the default entry
# - `bootctl set-oneshot`: the next boot tries it once; a power cycle returns to the default
#
# Debian's own BLS entries have no `devicetree` line and don't boot this laptop, so this
# script manages the entry itself (see docs/gotchas.md #17).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
REL=${1:?kernel release, e.g. 7.4.0-rc2-00012-gc363bab7cfcd}
DEBS=${2:-$HOME/code/zen-build}
NAME=${3:-asus-debian-next}
ESP=/boot/efi
D=$ESP/$NAME
DEFAULT=$(sed -n 's/^default //p' $ESP/loader/loader.conf)
T=$(mktemp -d)

echo "### default entry: $DEFAULT (left unchanged)"
[ "$DEFAULT.conf" != "$NAME.conf" ] && [ "$DEFAULT" != "$NAME.conf" ] || { echo "refusing to overwrite the default entry"; exit 2; }

echo "### 1. install linux-image-$REL"
if dpkg-query -W -f='${Status}' "linux-image-$REL" 2>/dev/null | grep -q 'install ok installed' && [ -f "/boot/initrd.img-$REL" ]; then
    echo "already installed"
else
    dpkg -i $(ls "$DEBS"/linux-image-"$REL"_*.deb | grep -v dbg)
fi

echo "### 2. initrd contents"
lsinitramfs "/boot/initrd.img-$REL" > "$T/initrd.txt"
miss=0
for pat in dm-crypt.ko dm-mod.ko sbin/cryptsetup cryptroot/crypttab msm.ko phy-qcom-edp.ko \
           panel-samsung-atna33xc20.ko nvme.ko dispcc-glymur.ko i2c-hid-of.ko qcom/gen8 "/$REL/"; do
    if grep -q -- "$pat" "$T/initrd.txt"; then echo "  ok      $pat"; else echo "  MISSING $pat"; miss=1; fi
done
[ $miss = 0 ] || { echo "initrd incomplete - not touching the ESP"; exit 3; }

echo "### 3. stage $D"
mkdir -p "$D"
cp "/boot/vmlinuz-$REL" "$D/linux.efi"
cp "/boot/initrd.img-$REL" "$D/initrd"
sh "$here/dtb-fixups.sh" "/usr/lib/linux-image-$REL/qcom/glymur-asus-zenbook-a14-ux3407na.dtb" \
    "$D/asus-ux3407na.dtb" --disable-sound
[ "$(fdtget "$D/asus-ux3407na.dtb" /sound status)" = disabled ]
fdtget "$D/asus-ux3407na.dtb" /soc@0/display-subsystem@ae00000 power-domain-names
sync

echo "### 4. entry $NAME.conf"
opts=$(sed -n 's/^options //p' "$ESP/loader/entries/$DEFAULT" 2>/dev/null || sed -n 's/^options //p' "$ESP/loader/entries/$DEFAULT.conf")
cat > "$ESP/loader/entries/$NAME.conf" <<EOT
title Debian ASUS A14 - $REL
sort-key 01-$NAME
linux /$NAME/linux.efi
devicetree /$NAME/asus-ux3407na.dtb
initrd /$NAME/initrd
options $opts
EOT
cat "$ESP/loader/entries/$NAME.conf"

echo "### 5. one-shot"
bootctl set-oneshot "$NAME.conf"
bootctl status --no-pager 2>/dev/null | grep -i oneshot || :
rm -rf -- "$T"
