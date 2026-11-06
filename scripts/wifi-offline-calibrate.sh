#!/bin/sh
# Encode the ASUS Wi-Fi board data (from the Windows qcwlancol8480 driver) into an updated
# ath12k board-2.bin inside a mounted root filesystem, under both board names ath12k asks for.
#   usage: wifi-offline-calibrate.sh <rootfs-mountpoint>
# Needs https://github.com/juergh/qcom-ath-board-update (pinned 63b4f4e4) at
# <rootfs>/opt/asus-wifi-tools and the BDF at the path below.
set -eu
root=$1
python3 - "$root" <<'PY'
import hashlib, sys
from pathlib import Path
root = Path(sys.argv[1])
bdf = root / 'usr/lib/firmware/updates/qcom/glymur/ASUSTeK/UX3407NA/bdwlan_qcc2072_1p0_ncm820A.elf'
# Post-BIOS-315/316 Windows driver 685.13804.110.0. Change deliberately if your driver differs.
expected = 'eeb1311ec3e4955323f1b62247d4caeaad1f292938e2077dfdc466d6a4d3be86'
actual = hashlib.sha256(bdf.read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit(f'BDF hash {actual} != expected {expected}')
sys.path.insert(0, str(root / 'opt/asus-wifi-tools/src'))
from qcom_ath_board_update.board import build_update
base = ('bus=pci,vendor=17cb,device=1112,subsystem-vendor=105b,subsystem-device=e14f,'
        'qmi-chip-id=33,qmi-board-id=255')
container = root / 'usr/lib/firmware/ath12k/QCC2072/hw1.0/board-2.bin'
output = root / 'usr/lib/firmware/updates/ath12k/QCC2072/hw1.0/board-2.bin'
output.parent.mkdir(parents=True, exist_ok=True)
# ath12k tries the variant name first, then the generic one.
for name in (base + ',variant=UX3407Q', base):
    source = output if output.exists() else container
    print(name, build_update(source, 'ath12k_pci', name, bdf, output,
                             root / 'opt/asus-wifi-tools/vendor/ath12k-bdencoder'))
PY
sync
