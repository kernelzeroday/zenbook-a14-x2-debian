# Gotchas

Things that cost real time on this machine, roughly in the order you'll hit them.

1. **Check the die, not the model name.** X2 Elite comes as Glymur (18-core) or Mahua (12-core),
   and the device trees are not interchangeable.
2. **Capture firmware after Windows Update has finished**, including BIOS updates. BIOS 315
   changed the ADSP image and the Wi-Fi BDF.
3. **Keep NVMe p1–p11.** They're Qualcomm firmware partitions, not Windows. Wipe only p12+.
4. **Don't boot the live system from USB-C** unless `qcom_q6v5_pas` is blacklisted. The ADSP
   restart resets the Type-C mux, and your root disk vanishes. The USB-A port is fine.
5. **"Last mounted" doesn't prove root never mounted.** Debian mounts it read-only first. Add `rw`
   to the command line if you want the journal on the stick.
6. **Penguins, then black screen** = the eDP link was trained at HBR2. Cap it at HBR.
7. **`nomodeset` doesn't help.** msm still probes the DP controllers and takes the link from efifb.
8. **The panel driver must be in the initramfs if `msm` is**, or the LUKS prompt lands on a dark
   screen. The same goes for the `gen80100_*` GPU firmware.
9. **Don't add a zap-shader node.** Linux runs at EL2 on these laptops ("All CPU(s) started at
   EL2"), so `Zap shader not enabled - using SECVID_TRUST_CNTL instead` is correct and expected.
   With a zap node, TrustZone rejects PAS init (`error -22 initializing firmware`) and the GPU
   never starts. That looks "stable" only because nothing is using the GPU.
10. **Your kernel config may not have `DM_CRYPT`.** arm64 defconfig plus the qcom fragments
    doesn't enable it.
11. ath12k may want **two** board names (with and without `variant=`). Add both.
12. Building one out-of-tree module from an existing build: use the **same `CROSS_COMPILE`**,
    or make rebuilds everything.
13. On firmware framebuffers (`efifb: scrolling: redraw`), each verbose console line costs about
    14 ms. `quiet splash` actually speeds up boot.
14. Speakers: **don't** enable the sound node with a generic topology. These amps need speaker
    protection.
15. **18 bpp on eDP** is an msm ordering bug (bpp chosen before link caps are read), not a
    panel limit. See patch 0002.
16. Rebuilding one module for a running kernel: pass `KERNELRELEASE=$(uname -r)`, or
    `LOCALVERSION_AUTO` puts your branch's hash into vermagic and modprobe refuses it.
17. Debian's `kernel-install` writes generic BLS entries with no `devicetree` line, and those
    don't boot this laptop. Mask `90-loaderentry.install` if you manage boot entries yourself.
18. **Unexplained silent resets under load:** While GPU power rails run on dummy regulators,
    high CPU transient spikes (boost up to 4.7 GHz across 18 cores) can cause instant reboots.
    Cap CPU frequency with `scripts/cpu mid` (~2.76 GHz) or `scripts/cpu low` (~2.2 GHz powersave)
    for stability during builds.
