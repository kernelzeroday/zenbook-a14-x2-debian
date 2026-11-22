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
<1620000000 2700000000>`) made the panel light up straight away. → patch 0001.

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

## 6. The silent reset, and a wrong fix

First session on the SSD: the machine reset while the user was picking a wallpaper. There was no
shutdown in the journal, no oops, and pstore was empty. The journal just stops, and the firmware
starts again about 10 s later.

**Wrong fix (published briefly as patches 0001/0002, then removed).** Every boot logs
`Zap shader not enabled - using SECVID_TRUST_CNTL instead`, and the a8xx code comment warns that
a wrong guess here leads to "a permissions violation". `glymur.dtsi` reserves
`gpu-microcode@919fe000` without linking it, so I wired up a zap-shader node with the Windows
`qcdxkmsuc8480.mbn`. The resets stopped, but only because the GPU no longer started:

```
adreno 3d00000.gpu: error -22 initializing firmware qcom/glymur/ASUSTeK/UX3407NA/qcdxkmsuc8480.mbn
msm_dpu ...: [drm:adreno_load_gpu [msm]] *ERROR* gpu hw init failed: -22
```

TrustZone rejects `qcom_pas_init_image()` for the GPU (PAS 13), while the ADSP/CDSP load fine over
the same path. The reason: **this machine boots Linux at EL2** ("CPU: All CPU(s) started at
EL2", VHE, `/dev/kvm`). Upstream's `*-el2.dtso` overlays all disable the zap shader: *"We can't
and don't need to use zap shader in EL2 as linux can zap the gpu on its own."* So Glymur leaving
the node out is correct.

What was missing was a check of the GPU's own state after the change. "No crash" isn't the same
as "fixed".

**Status:** zap node removed again, and the cause of the reset is unknown. Next step is to capture
evidence (live kernel log streamed off the machine, and ramoops) instead of guessing.

As an immediate mitigation against hard resets under sustained load / parallel builds, the CPU
frequency was throttled via cpufreq (`scripts/cpu`):
- `mid` profile: ~2.76 GHz, `schedutil` governor (tested stable under parallel compiles)
- `low` profile: ~2.2 GHz, `powersave` governor (stress/build tasks)
The unthrottled maximum on Oryon v1 approaches ~4.7 GHz, where transient load spikes appear to
trigger hardware brownout or PMIC reset while GPU regulators run as unmapped dummies.

## 7. Banding (18 bpp)

`dp_debug` showed `bpp = 18` after every boot. `msm_dp_display_set_mode()` runs at mode_set, and
it picks the bpp with `msm_dp_panel_get_supported_bpp()`: the highest depth whose data rate fits
in `num_lanes × rate × 8`. For eDP, `link_info` is only filled in by `msm_dp_hpd_plug_handle()`
from `msm_dp_display_prepare_link()`, which runs *after* mode_set. On the first enable the
capacity is therefore 0, nothing fits, and the loop falls through to the 18 bpp minimum. A later
modeset (fb blank/unblank) had real link info and picked 30 bpp at HBR2.

At HBR × 2 the link carries 4.32 Gbps, and 1920×1200@60 at 24 bpp needs 3.70 Gbps, so 24 bpp is
the right answer. Patch 0002 re-runs the mode setup for eDP right after the plug handling. That's
a generic msm fix, unlike the community tree's A14-gated depth patch. Verified on hardware:
`dp_debug` reports `bpp = 24` at `rate=270000 num_lanes=2`.

Building one module against a running kernel: `make KERNELRELEASE=<running release> modules`.
`LOCALVERSION_AUTO` otherwise stamps the patched branch's hash into the vermagic, and the module
won't load.

## 8. Vanilla 7.4-rc2: three black screens (Nov 10)

7.4-rc2 was tagged on Nov 8, but `linux-msm/laptops-kernel` was still on rc1. Looking at why we
were on that fork at all: nobody chose it. qcom-deb-images builds its laptop flavour from
`laptops-kernel --ref qcom-laptops`, the builder pinned that tip, and every later session
inherited the pin. Vanilla v7.4-rc1 already had the UX3407NA DTS, `glymur.dtsi` and the EC
driver. So the move was to vanilla rc2 plus this repo's patches. rc1→rc2 itself is quiet for this
machine: no functional Qualcomm, msm, dm or SCMI changes, just the tree-wide `kmalloc_obj`
conversion, plus an arm64 fix that saves `TPIDR2_EL0` across CPU suspend (SME is on all 18 cores).

The first vanilla build, with patches 0001–0003, booted to a black panel. The caps lock LED
worked, so the kernel was alive. It took three rounds, each one fixing a real problem:

1. **MDSS INT2 power domain.** In the fork, Glymur's display subsystem has two power domains
   (`core`, `int2`) and the driver powers both. Vanilla only knows `core`, so the SSPPs behind
   INT2 (VIG2/3, DMA5/6) stay unpowered. Patches 0004 (driver) and 0008 (DT). The eDP fixes
   0005–0007 came over with them.
2. **CLX on the Adreno X2-85.** Vanilla 7.4 sends the CLX/IFF current-limit tables to the GMU. On
   Glymur (CRD, Yoga Slim 7x, and this A14), the GMU then wedges on the next BW vote. msm binds
   the GPU and display as one component device, so a GPU that never initializes kills the
   display too. Patch 0009 is Abel Vesa's revert from the fork.
3. **The eDP PHY.** With `drm.debug=0x106` and the LUKS passphrase typed blind, the boot finally
   left a journal. The GPU was up, and eDP training failed in clock recovery at 2.7 Gbps × 2:
   the sink asked for more swing on every try, lane status stayed `00`, and it ended in
   `max v_level reached`. That rate and lane count work on rc1, so the fault was
   physical-layer. Vanilla's `phy-qcom-edp.c` has no Glymur (v8) power-on, PLL, PCS and lane
   sequence and drives the PHY with older-generation settings. Patches 0010–0012 (Bjorn
   Andersson, plus Abel Vesa's fixup) bring it over. After that: `link training #1/#2 … successful`,
   `bpp = 24`.

How to find the next one faster than this: list `lsmod` on the kernel that works, map every
module to its source directory, and diff those directories against the new tree with the
allocator churn filtered out. That sweep turned up the PHY driver straight away. An earlier
by-hand diff had used `drivers/phy/qcom` (which doesn't exist) and wrongly reported "no change".

Still only in the fork, and not needed for the internal panel: the Glymur USB-C DP PHY fixes in
`phy-qcom-qmp-combo.c`, the gcc-glymur USB/PCIe GDSC tweaks, audio (LPASS, SoundWire), Iris
video, the camera, CoreSight, and the SPEL powercap driver.

Vanilla's DTB enables `/sound`. `install-kernel-esp.sh` turns it off (gotcha 14).

Shortly after the first good rc2 boot, the machine powered off instantly at firmware level,
with no log. The CPU cap had been forgotten after the reboot (it isn't persistent). It's
persistent now: [`config/systemd/zen-cpu-cap.service`](../config/systemd/zen-cpu-cap.service).

## 9. 7.4-rc3 and the early-boot power-off (Nov 22)

rc3 (`aebb72744764`) changes nothing this machine needs: no Glymur, msm, eDP PHY or power fixes.
All twelve patches apply unchanged, and none of them are upstream yet. It was built with rc2's
`/proc/config.gz` as the base config, through `guarded-make.sh` at the 2.2 GHz cap (about 1 h 50 min,
no thermal pauses at ~40 °C). It went onto the ESP as a separate entry (`asus-debian-rc3`) and
was armed as a one-shot boot, with rc2 kept as the default.

The one-shot boot died about 14.7 s after kernel start: the LUKS passphrase was accepted, the
journal flushed to disk, and then the log stops. There was no oops or panic, and pstore was empty.
The laptop came back up at the systemd-boot menu (the one-shot had been used up). Choosing rc3
by hand then booted normally, and it has stayed up since.

The timing matters. `zen-cpu-cap.service` is ordered `After=sysinit.target`, about 1 s after
journald starts. The reset happened inside that gap, while udev coldplug loads modules on all 18
cores at uncapped clocks. That's the same firmware-level power-off as before (§8), just in a
window the service never covered. It doesn't look like an rc3 problem.

The fix is to apply the cap from the initramfs. `cpufreq` (SCMI) is built in, so the policies
exist before `/init` runs. [`config/initramfs/scripts/init-top/zen-cpu-cap-early`](../config/initramfs/scripts/init-top/zen-cpu-cap-early)
sets `scaling_max_freq` to the highest step at or below 2.208 GHz on every policy, and logs
`zen-cpu-cap-early:` lines to the kernel log. The powersave governor is a module, so the
script only sets the frequency limit. The systemd service still runs afterwards and switches
the governor. The installers put the script in place, and `update-initramfs -u` picks it up.

That leaves kernel start to `/init` (about 12.5 s, mostly driver probing) running at the
firmware's default clocks. If a reset ever shows up that early, the next step is a cap set by
the kernel itself.

## 10. Open

- Bluetooth NVM/calibration files, speaker protection and topology, HDMI, suspend.
- Port the qmp-combo USB-C DP fixes; test external displays.
- Root-cause the firmware-level power-off under load, now that it's known to be load-driven
  (it happens during boot-time module loading too, not only during builds).
- Promote rc3 to default after a few days of use.
