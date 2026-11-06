# Bring-up log

Chronological, including the wrong turns. Dates are 2026, times are local unless noted.

## 0. Prologue: the wrong laptop (Oct 30)

The first target was a Lenovo Yoga Slim 7x. The unit that arrived was the 6-core X2 variant, not
the 18-core Glymur part the Lenovo device tree describes. It got as far as kernel output and then
panicked about 8 s in, every time. It went back. Lesson: on Snapdragon, **the SKU's die matters**.
Glymur (18-core X2 Elite) and Mahua (12-core) need different device trees, and the retail listing
won't tell you which one you're getting.

The tooling built for that attempt (debos image, Windows-side firmware capture over a bootstrap
SSH, a USB writer that verifies every byte it writes) carried over.

## 1. Preparation (Nov 5)

- Windows set up with an offline account; OpenSSH bootstrapped from a hosted PowerShell script,
  because "Optional features" refused to install it.
- Captured before touching anything:
  - all 2,782 DriverStore files, each SHA256-verified
  - the hardware inventory
  - the Wi-Fi `BDFileName` from the registry
  - a raw copy of NVMe p1–p11
- BIOS went 310 → 315 → 316 through Windows Update. 315 changed the ADSP firmware and the Wi-Fi
  BDF, so the firmware was captured again afterwards. **Capture firmware after updating, not before.**
- Kernel: `linux-msm/laptops-kernel` at `23b349cb9eb1` (7.4-rc1), which has
  `glymur-asus-zenbook-a14-ux3407na.dts`.
- Image: qcom-deb-images (trixie) with that kernel, the ASUS firmware, the A14 DTB loaded through
  systemd-boot's `devicetree`, and the speaker sound node disabled.

## 2. First boot: penguins, then black

The kernel booted (the fbcon penguins appeared, one per CPU), then the screen went dark. Caps Lock
still toggled, so the machine was alive. The root filesystem's "last mounted" time hadn't changed.

*Wrong conclusion:* "root never mounted, USB is dead in the initramfs". I added `qcom_q6v5_pas` and
the PMIC/Type-C stack to the initramfs, on the theory that the Type-C ports need the ADSP.

*What was actually happening:* Debian mounts root **read-only** first, and a read-only mount
doesn't update "last mounted". The Fedora WoA install guide explains it: when the kernel's
`qcom_q6v5_pas` reboots the ADSP into the full firmware, the TCPM resets and the Type-C mux goes
high-impedance. To xHCI, that looks like the USB-C stick being unplugged. Root disappears
mid-boot. My initramfs change made this happen *earlier*.

**Fix:** boot the live image from **USB-A** (the `usb_mp` port behind PTN3222 repeaters doesn't
depend on the ADSP), and/or use `modprobe.blacklist=qcom_q6v5_pas`. With `rw` on the command line
the journal persisted, and showed a full boot to `getty` and `sshd`, behind a dark screen.

## 3. The dark screen

Live over SSH (Wi-Fi was working by then, see §4):

- `efifb` comes up at 1920×1200, and the console moves onto it (the penguins).
- About 1 s later, `msm-dp-display` probes the eDP controller, and the picture disappears.
- With `nomodeset`, msm can't bind (`adev bind failed: -19`). Nothing drives the panel, but msm
  has already taken the link over.
- Without `nomodeset`, msm binds. `eDP-1` reads connected and enabled at 1920×1200. `fb0` is
  `msmdrmfb`. The CRTC is active. Backlight 2047/2047. `dp_debug`: `rate=540000 num_lanes=2`.
  **The screen is still black.**
- Forcing a modeset (fb blank/unblank) went to 30 bpp. Still black.

The community A14 NixOS tree (chrispouliot/linux-zenbook-a14-arm) caps the eDP link at HBR, as a
workaround for training failures after s2idle. Applying that cap here (`link-frequencies =
<1620000000 2700000000>`) made the panel light up straight away. → patch 0003.

## 4. Wi-Fi

ath12k (`ath12k_wifi7_pci`) asked for board data for two names: one with `variant=UX3407Q` and one
without. The stock `board-2.bin` has neither. The ASUS BDF from the Windows driver
(`bdwlan_qcc2072_1p0_ncm820A.elf`) was encoded into an updated `board-2.bin` under both names, with
`qcom-ath-board-update`, offline, into the image. The on-device helper written beforehand refused,
because it expected exactly one failing name.

## 5. Installing to the NVMe

- p12–p16 (Windows) deleted, p1–p11 kept, new 1 GiB ESP + LUKS2 partition created.
- `cryptsetup open` → `device-mapper: table: crypt: unknown target type`. The kernel had
  `# CONFIG_DM_CRYPT is not set`. Built `dm-crypt.ko` against the same tree.
  - A single-target `make drivers/md/dm-crypt.ko` fails at modpost: it can't see `dm-mod`'s
    exports.
  - `make modules` works, but rebuilt the whole tree because `CROSS_COMPILE` differed from the
    original build. It still produced a module with the identical vermagic (no modversions or
    module signing).
- rsync'd the running USB root into the LUKS volume, wrote crypttab/fstab, and added to the
  initramfs: dm-crypt, NVMe, the I2C-HID keyboard stack (`gpi`, `i2c_qcom_geni`, `i2c_hid_of`,
  `hid_asus`), and the display stack.
- **The display stack had to go in completely.** `MODULES=most` had pulled `msm` in but not
  `panel_samsung_atna33xc20`. That means msm would grab the eDP controller in the initramfs, then
  wait for a panel driver that's sitting on the still-locked root, leaving the passphrase prompt
  on a dead screen. The GPU's `gen80100_*` firmware needed an initramfs hook for the same reason.
- GNOME (`task-gnome-desktop` + `tasksel install standard laptop english`, the Debian-installer
  equivalent), Plymouth with `quiet splash`.
- `efibootmgr` writes worked on this firmware. Added a "Debian" boot entry and removed the stale
  Windows one.

## 6. The silent reset

First session on the SSD: the machine reset while the user was picking a wallpaper. There was no
shutdown in the journal, no oops, and pstore was empty. The journal just stops, and the firmware
starts again about 10 s later.

The one odd line on every boot:

```
msm_dpu ae01000.display-controller: Zap shader not enabled - using SECVID_TRUST_CNTL instead
```

The a8xx driver's own comment says that if the guess is wrong, *"access to the
RBBM_SECVID_TRUST_CNTL register will be blocked and a permissions violation will soon follow"*.
On Qualcomm, a permissions violation means an XPU fault, and the secure world resets the SoC
without a log. `glymur.dtsi` reserves `gpu-microcode@919fe000`, but never links it to the GPU.
hamoa (X1E) has `gpu_zap_shader: zap-shader { memory-region = <&gpu_microcode_mem>; }`. The ASUS
zap shader is `qcdxkmsuc8480.mbn` from the Windows display driver.

After adding the node (patches 0001/0002), the warning is gone and the wallpaper changes are
stable. GNOME runs GPU-accelerated on Mesa 26.1.6 (trixie-backports).

## 7. Banding (18 bpp)

`dp_debug` showed `bpp = 18` after every boot. `msm_dp_display_set_mode()` runs at mode_set, and
it picks the bpp with `msm_dp_panel_get_supported_bpp()`: the highest depth whose data rate fits
in `num_lanes × rate × 8`. For eDP, `link_info` is only filled in by `msm_dp_hpd_plug_handle()`
from `msm_dp_display_prepare_link()`, which runs *after* mode_set. On the first enable the
capacity is therefore 0, nothing fits, and the loop falls through to the 18 bpp minimum. A later
modeset (fb blank/unblank) had real link info and picked 30 bpp at HBR2.

At HBR × 2 the link carries 4.32 Gbps, and 1920×1200@60 at 24 bpp needs 3.70 Gbps, so 24 bpp is
the right answer. Patch 0004 re-runs the mode setup for eDP right after the plug handling. That's
a generic msm fix, unlike the community tree's A14-gated depth patch.

Building one module against a running kernel: `make KERNELRELEASE=<running release> modules`.
`LOCALVERSION_AUTO` otherwise stamps the patched branch's hash into the vermagic, and the module
won't load.

## 8. Open

- Bluetooth NVM/calibration files, speaker protection and topology, HDMI, suspend.
