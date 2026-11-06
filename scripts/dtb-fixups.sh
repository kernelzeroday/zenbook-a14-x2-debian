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

# Patch 0003: the internal OLED stays dark at HBR2; allow RBR/HBR only (1.62/2.7 Gbps).
fdtput -t x "$out" /soc@0/display-subsystem@ae00000/displayport-controller@af6c000/ports/port@1/endpoint \
    link-frequencies 0 608f3d00 0 a0eebb00

# Patches 0001+0002: link the reserved zap-shader carveout to the GPU, or the a8xx driver
# writes SECVID_TRUST_CNTL itself and the secure world later resets the SoC.
if ! fdtget "$out" /soc@0/gpu@3d00000/zap-shader firmware-name >/dev/null 2>&1; then
    phandle=$(fdtget -t x "$out" /reserved-memory/gpu-microcode@919fe000 phandle 2>/dev/null || true)
    if [ -z "$phandle" ]; then
        max=$(dtc -I dtb -O dts "$out" 2>/dev/null | grep -oE 'phandle = <0x[0-9a-f]+>' |
              grep -oE '0x[0-9a-f]+' | sort -u | xargs printf '%d\n' | sort -n | tail -1)
        phandle=$(printf '%x' $((max + 1)))
        fdtput -t x "$out" /reserved-memory/gpu-microcode@919fe000 phandle "$phandle"
    fi
    fdtput -c "$out" /soc@0/gpu@3d00000/zap-shader
    fdtput -t x "$out" /soc@0/gpu@3d00000/zap-shader memory-region "$phandle"
    fdtput -t s "$out" /soc@0/gpu@3d00000/zap-shader firmware-name qcom/glymur/ASUSTeK/UX3407NA/qcdxkmsuc8480.mbn
fi
# Upstream DT produces many harmless dtc warnings; only fail if it no longer decompiles.
dtc -q -I dtb -O dts "$out" -o /dev/null 2>/dev/null
echo "Wrote $out"
