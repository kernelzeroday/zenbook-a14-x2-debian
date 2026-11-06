#!/bin/sh
# Apply this repo's fixes to an already-compiled, *unpatched* UX3407NA DTB.
# If you built the kernel with patches/kernel applied, you only need --disable-sound.
#   usage: dtb-fixups.sh <in.dtb> <out.dtb> [--disable-sound]
set -eu
in=$1 out=$2
cp "$in" "$out"

# Keep the speaker sound card off until speaker protection is validated.
if [ "${3:-}" = --disable-sound ]; then
    fdtput -t s "$out" /sound status disabled
fi

# Patch 0001: the internal OLED stays dark at HBR2; allow RBR/HBR only (1.62/2.7 Gbps).
fdtput -t x "$out" /soc@0/display-subsystem@ae00000/displayport-controller@af6c000/ports/port@1/endpoint \
    link-frequencies 0 608f3d00 0 a0eebb00

# Deliberately no zap-shader node: Linux runs at EL2 here and zaps the GPU itself.
# Upstream DT produces many harmless dtc warnings; only fail if it no longer decompiles.
dtc -q -I dtb -O dts "$out" -o /dev/null 2>/dev/null
echo "Wrote $out"
