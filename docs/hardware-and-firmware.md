# Hardware and firmware inventory

Everything here was read from the machine itself (Windows CIM/registry before the wipe, Linux
sysfs/dmesg after). Serial numbers, MAC addresses and license data are intentionally omitted.

## Machine

| | |
|---|---|
| Model | ASUS Zenbook A14 **UX3407NA** (DMI product `Zenbook A14 UX3407NA`) |
| SoC | Snapdragon X2 Elite **X2E88100**, 18 Oryon cores (Glymur) |
| RAM | 16 GiB (Samsung) |
| SSD | Micron **MTFDKBA512QHK** 512 GB NVMe (PCIe Gen4 x4) |
| Panel | Samsung **ATNA40CT06** OLED 1920×1200@60, eDP on `mdss_dp3` (`af6c000`) |
| GPU | Adreno **X2-90** (`qcom,adreno-44070001`, gen8 / a8xx, firmware `gen80100_*`) |
| Wi-Fi/BT | Qualcomm FastConnect **C7700 NCM820A** (QCC2072), PCI `17cb:1112` subsystem `105b:e14f` |
| Keyboard | I2C-HID `0B05:4B42` |
| Touchpad | I2C-HID `04F3:3315` (ELAN) |
| BIOS | shipped `UX3407NA.310`, Windows Update applied **315**, then **316** (2026-10-22) — current |

## NVMe layout as shipped

Partitions 1–11 are Qualcomm firmware partitions used by the platform firmware. **Do not delete
them.** Only 12–16 belong to Windows.

| # | Size | GPT name | Notes |
|---|---|---|---|
| 1 | 1 MiB | ToolsFv | non-zero payload |
| 2 | 16 MiB | LogFs | |
| 3 | 1 MiB | EnterpriseFV | |
| 4 | 1 MiB | ToolsFv_BACKUP | non-zero payload |
| 5 | 70 MiB | UpdateCapsule | |
| 6 | 120 MiB | NHLOS | |
| 7 | 120 MiB | core_nhlos_a | |
| 8–10 | 1 MiB each | quantumsdk, quantumfv, catecontentfv | |
| 11 | 512 MiB | logdump | |
| 12 | 450 MiB | EFI system partition | Windows boot + a stale `UX3407NA.310.cap` |
| 13 | 16 MiB | Microsoft reserved | |
| 14 | 473.8 GiB | Basic data (BitLocker) | C: |
| 15 | 1.6 GiB | Basic data (NTFS) | WinRE |
| 16 | 260 MiB | Basic data (FAT) | `AsusWinRE` tools |

After install: p1–p11 untouched, p12 = 1 GiB ESP, p13 = LUKS2 (rest of disk).

## Windows driver packages (after BIOS 315/316 updates)

| Package (DriverStore) | Version | Provides |
|---|---|---|
| `qcsubsys_ext_adsp8480.inf` | 5200.1810.0.5 (newest of two installed) | `qcadsp8480.mbn`, `adsp_dtbs.elf`, `adsp*.jsn` |
| `qcsubsys_ext_soccp8480.inf` | 685.13804.70.1 | `soccpr.jsn` |
| `qcnspmcdm8480.inf` | 30.0.220.11010 | `qccdsp8480.mbn`, `cdsp_dtbs.elf` |
| `qcdx8480.inf` (Adreno X2-90 driver 32.0.149.0) | 32.0.149.0 | `qcdxkmsuc8480.mbn` (**GPU zap shader**) |
| `qcwlancol8480.inf` | 685.13804.110.0 (active, `oem165.inf`) | `bdwlan_qcc2072_1p0_ncm820A.elf` (Wi-Fi board data) |

The Wi-Fi board file is the one named by the active adapter's registry `BDFileName` value.
Don't pick it by newest timestamp: there are several `bdwlan_*` files.

## Firmware files used (NOT included in this repo)

Installed to `/usr/lib/firmware/updates/qcom/glymur/ASUSTeK/UX3407NA/`. Hashes are from the
post-BIOS-316 Windows install. Yours should match if you're on the same driver versions.

| File | Bytes | SHA256 |
|---|---:|---|
| `qcadsp8480.mbn` | 19867608 | `67b4e129d4d60fccd05d85be3754168f46535549a03a3627c598d634e73df49d` |
| `adsp_dtbs.elf` | 225080 | `7906466c734b2f360d48cf086f80b6e04d84e9b02255c74545aa28d5df1e932c` |
| `adspr.jsn` | 513 | `66ce8531efb7979d234e0f0eabbe18d038ac97da771a8a194f613df8f0724e81` |
| `adsps.jsn` | 515 | `12ac2f3ae8ced12aa4b06b3ab3a01bc4d8efe1c92ebea503c002f209a6ec176f` |
| `adspua.jsn` | 703 | `982a99853495e34726b8e44697fdfad303334de0a67cbf6cde306c8f1731000b` |
| `qccdsp8480.mbn` | 3252504 | `acf13d29288d283793f418a36650e8a261eed927d30de109a59cb2210f458794` |
| `cdsp_dtbs.elf` | 69432 | `9bee104a48d4aac647287d6c1454df170c1cff7158a2352711fd1e2163ea6d1d` |
| `soccpr.jsn` | 261 | `e6b053e996f2d6b933f41bd6dffe4a5ba3c09ec594675febee04c944b3780d6a` |
| `qcdxkmsuc8480.mbn` | 12088 | `bd1a2d6735dc0507ace397ab868c05d70b286a30ea4a57e16771e272a045b5db` |
| `bdwlan_qcc2072_1p0_ncm820A.elf` | 125476 | `eeb1311ec3e4955323f1b62247d4caeaad1f292938e2077dfdc466d6a4d3be86` |

The BIOS 315 update changed `qcadsp8480.mbn`, `adsp_dtbs.elf` and the Wi-Fi BDF. Before it, the
BDF hash was `960e9e93da708f5e1086ce15d82d3e44d846ec9441eac40e1725467d357965d8`.

Firmware loaded from `linux-firmware` / Debian packages (not board-specific):
`qcom/gen80100_sqe.fw`, `qcom/gen80100_gmu.bin`, `qcom/gen80100_aqe.fw` (GMU firmware v5.2.38),
`ath12k/QCC2072/hw1.0/{firmware-2.bin,board-2.bin}`.

Still missing: `qca/ornnv11.b17`, `qca/ornbcscal11.b17` (Bluetooth), and SoCCP `soccp.mbn`, which
isn't in the Windows DriverStore. The SoCCP is already running at boot (early_boot / attach path).

## Kernel identifiers seen at runtime

- ath12k board names (both are needed in `board-2.bin`):
  - `bus=pci,vendor=17cb,device=1112,subsystem-vendor=105b,subsystem-device=e14f,qmi-chip-id=33,qmi-board-id=255,variant=UX3407Q`
  - same without `,variant=UX3407Q`
- ath12k firmware: `WLAN.COL.1.0.c2-00277-QCACOLSWPL_V1_TO_SILICONZ-1` (build 2024-09-11)
- eDP: `rate=270000 num_lanes=2` after the HBR cap; 18 bpp
- dpu hardware revision `0xc0020000`
