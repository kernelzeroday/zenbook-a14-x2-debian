# Debian on the ASUS Zenbook A14 (UX3407NA, Snapdragon X2 Elite)

Notes, patches and scripts from bringing up **Debian 13 (trixie) + GNOME with LUKS2 full-disk
encryption** on the ASUS Zenbook A14 UX3407NA — the Snapdragon X2 Elite (Glymur, X2E88100,
18-core) version — using a Linux **7.4-rc1** kernel from
[`linux-msm/laptops-kernel`](https://github.com/linux-msm/laptops-kernel).

This laptop gained a mainline device tree in Linux 7.4. "Supported in mainline" turned out to
mean "boots, then needs a handful of very specific fixes". This repo records every one of them,
with root causes, so the next person doesn't have to rediscover them.

> **No firmware is redistributed here.** The DSP and Wi-Fi calibration files are
> proprietary Qualcomm/ASUS blobs. You extract them from *your own* machine's Windows install
> before wiping it. [docs/hardware-and-firmware.md](docs/hardware-and-firmware.md) lists the exact
> files, the Windows driver packages they come from, and SHA256 hashes so you can verify yours.

## Status (2026-11-06, BIOS UX3407NA.316)

| Area | State | Notes |
|---|---|---|
| Boot (systemd-boot, DT via `devicetree`) | ✅ | Secure Boot must be off |
| Internal NVMe, LUKS2 root, Plymouth prompt | ✅ | Kernel needed `CONFIG_DM_CRYPT` |
| Internal OLED (eDP) | ✅ | Needs [HBR cap](patches/kernel/0001-arm64-dts-qcom-glymur-asus-zenbook-a14-Limit-the-eDP.patch); 24 bpp with [the bpp fix](patches/kernel/0002-drm-msm-dp-Recompute-eDP-bpp-once-the-link-capabilit.patch) |
| GPU (Adreno X2-90) | ⚠️ | Mesa 26.1 (trixie-backports). **One unexplained silent reset under GPU load, under investigation.** No zap shader (EL2, see below) |
| Wi-Fi (QCC2072 / FastConnect C7700) | ✅ | Needs board data from the Windows driver ([script](scripts/wifi-offline-calibrate.sh)) |
| Keyboard, touchpad | ✅ | I2C-HID |
| Battery / charger status | ✅ | Needs ADSP running (qcom_q6v5_pas) |
| USB-A | ✅ | |
| USB-C data | ✅ | Booting *from* USB-C needs `modprobe.blacklist=qcom_q6v5_pas` |
| Bluetooth | ⚠️ | Controller up; `qca/ornnv11.b17` + `ornbcscal11.b17` missing |
| Speakers | ⛔ | Sound node deliberately disabled until speaker protection is validated |
| HDMI / USB-C DP alt-mode | ❓ | Untested; known incomplete upstream |
| Suspend | ❓ | Untested |

## What was wrong, in one table

| Symptom | Root cause | Fix |
|---|---|---|
| Boot from USB-C hangs in initramfs | ADSP restart by `qcom_q6v5_pas` resets the Type-C mux; root disk vanishes | Boot from USB-A, or `modprobe.blacklist=qcom_q6v5_pas` while running from USB |
| Screen goes dark right after the fbcon penguins | msm takes the eDP link from efifb and trains HBR2; panel never lights | [Cap eDP at HBR](patches/kernel/0001-arm64-dts-qcom-glymur-asus-zenbook-a14-Limit-the-eDP.patch) |
| `cryptsetup open`: `crypt: unknown target type` | defconfig + qcom-deb-images fragments don't enable `DM_CRYPT` | [`config/kernel/a14-luks.config`](config/kernel/a14-luks.config) |
| Random hard reset (no log, empty pstore) under GPU load | **Unknown.** It is *not* the missing zap shader: Linux runs at EL2 here, and a zap node makes TrustZone reject it (`-EINVAL`), so the GPU never starts | Under investigation ([log §6](docs/bringup-log.md#6-the-silent-reset-and-a-wrong-fix)). Capping CPU to 2.2–2.76 GHz ([`scripts/cpu`](scripts/cpu)) mitigates transient brownout |
| ath12k: `failed to fetch board data … variant=UX3407Q` | Laptop-specific BDF only exists in the Windows driver | [Encode the Windows BDF into `board-2.bin`](scripts/wifi-offline-calibrate.sh) |
| Passphrase prompt could come up dark | `msm` in initramfs but not the panel driver | [`config/initramfs/modules`](config/initramfs/modules) |
| Banding | eDP `mode_set` picks bpp before the link caps are read → 18 bpp | [Recompute bpp after plug handling](patches/kernel/0002-drm-msm-dp-Recompute-eDP-bpp-once-the-link-capabilit.patch) → 24 bpp verified |

The full narrative, including the dead ends, is in [docs/bringup-log.md](docs/bringup-log.md).
Short version of the lessons: [docs/gotchas.md](docs/gotchas.md).

## Repository layout

```
patches/kernel/     git format-patch series against linux-msm/laptops-kernel (checkpatch --strict clean)
config/kernel/      kernel config fragment
config/initramfs/   initramfs-tools module list and hooks
config/boot/        systemd-boot loader + entries (USB live and internal LUKS)
scripts/            image build, DTB fixups, Wi-Fi calibration, USB writer, NVMe install
docs/               bring-up log, hardware/firmware inventory, gotchas, sources
```

## Reproducing (outline)

1. **Before touching Windows:** back up the firmware files listed in
   [docs/hardware-and-firmware.md](docs/hardware-and-firmware.md) from
   `C:\Windows\System32\DriverStore\FileRepository`, and the Qualcomm firmware partitions
   (NVMe p1–p11). Turn off Secure Boot.
2. Build the kernel: [`scripts/build-kernel.sh`](scripts/build-kernel.sh) (pins the laptops-kernel
   commit, applies [`patches/kernel`](patches/kernel), adds the config fragment).
3. Build the image from [qcom-deb-images](https://github.com/qualcomm-linux/qcom-deb-images) and
   run [`scripts/prepare-image.sh`](scripts/prepare-image.sh) (installs kernel, firmware, DTB,
   initramfs fixes, boot entry).
4. Write it to a **USB-A** stick with [`scripts/write-usb.py`](scripts/write-usb.py), boot it
   (Esc boot menu), and get on the network.
5. Install to the NVMe with [`scripts/install-to-nvme.sh`](scripts/install-to-nvme.sh): keeps
   firmware partitions p1–p11, replaces the Windows partitions with ESP + LUKS2, copies the
   system, installs GNOME + Plymouth.

The scripts are what was actually run, lightly generalised. They are written for this exact
model and refuse other hardware in places. Read them before running them.

## License

Kernel patches: GPL-2.0 (same as the kernel). Everything else: MIT, see [LICENSE](LICENSE).
Not affiliated with ASUS, Qualcomm or Debian.
