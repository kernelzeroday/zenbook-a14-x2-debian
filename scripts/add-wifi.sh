#!/bin/sh
# Add a WPA-PSK NetworkManager connection to a mounted root filesystem so the live image
# joins Wi-Fi on first boot (handy while the panel is still dark). Prompts; nothing is logged.
#   usage: add-wifi.sh <rootfs-mountpoint>
set -eu
root=$1
printf 'SSID: '; IFS= read -r ssid
printf 'Password: '; stty -echo; IFS= read -r psk; stty echo; echo
[ -n "$ssid" ] && [ ${#psk} -ge 8 ] || { echo 'SSID empty or password shorter than 8 characters' >&2; exit 1; }
file="$root/etc/NetworkManager/system-connections/live-wifi.nmconnection"
umask 077
cat > "$file" <<EOF
[connection]
id=live-wifi
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
ssid=$ssid

[wifi-security]
key-mgmt=wpa-psk
psk=$psk

[ipv4]
method=auto

[ipv6]
method=auto
EOF
chown 0:0 "$file"
chmod 600 "$file"
echo "Saved $file - the image now contains this password; treat it accordingly."
