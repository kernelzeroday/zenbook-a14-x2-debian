# Sources

## Kernel and device tree
- Vanilla Linux v7.4-rc2 (`7475ea8b5861`), current base: https://github.com/torvalds/linux
- Vanilla Linux v7.4-rc3 (`aebb72744764`), on trial; patches 0001–0012 apply unchanged
- Fork commits carried as patches 0004–0012 (from laptops-kernel `qcom-laptops`, Nov 2026):
  `0e7e4ba2c363` drm/msm/mdss INT2_GDSC (Yongxing Mou), `e3730e0a7a7a` force_link_train (Saurabh Anand),
  `6753adf3054a` eDP 1.4 LINK_RATE_SET (Jesse Casco), `ba7a445631dc` eDP native lane count (Tyler Baker),
  `b11d88a5bad0` DT INT2_GDSC (Yongxing Mou), `ed084ac4a9c0` revert X2-85 CLX (Abel Vesa),
  `26a09422e9e2` + `59625743e069` eDP PHY v8 sequence (Bjorn Andersson), `340c3d7264fa` fixup (Abel Vesa)
- CLX revert rationale (GMU wedges after the CLX tables on Glymur, incl. this A14):
  https://lore.kernel.org/all/20260516-a8xx-clx-support-v1-3-62508bf651ac@oss.qualcomm.com/
- (Original bring-up) linux-msm laptops kernel (qcom-laptops branch), 7.4-rc1, pinned commit `23b349cb9eb1aefd226da1debd86011bdb86f57f`:
  https://github.com/linux-msm/laptops-kernel
- Phoronix, "Linux 7.4 To Upstream Support For Three Snapdragon X2 Elite Laptops":
  https://www.phoronix.com/news/ASUS-UX3407NA-Linux-7.4
- UX3407NA DTS series on linux-arm-msm ("[PATCH 0/3] arm64: dts: qcom: Introduce Asus Zenbook A14 (UX3407NA)"):
  https://ratatoskr.run/linux-arm-msm/2026/06/17163526/t
- `drivers/gpu/drm/msm/adreno/a8xx_gpu.c`: zap shader / `SECVID_TRUST_CNTL` fallback
- `arch/arm64/boot/dts/qcom/*-el2.dtso`: upstream disables the zap shader when Linux runs at EL2

## Community work on this exact laptop
- chrispouliot/linux-zenbook-a14-arm, NixOS/Arch guide and patch stack for the UX3407NA
  (eDP HBR cap, eDP depth patch, initramfs module list, EC driver use):
  https://github.com/chrispouliot/linux-zenbook-a14-arm

## Snapdragon laptop install guides
- Fedora wiki, Snapdragon WoA Laptop Install (ADSP / Type-C reset, `qcom_q6v5_pas` blacklist):
  https://fedoraproject.org/wiki/Snapdragon_WoA_Laptop_Install
- Ubuntu Concept on Snapdragon X Elite (initramfs modules, `*_ignore_unused` parameters):
  https://discourse.ubuntu.com/t/ubuntu-concept-snapdragon-x-elite/48800

## Qualcomm
- Linux on Snapdragon X2 developer preview: https://www.cnx-software.com/2026/09/25/qualcomm-releases-linux-developer-preview-snapdragon-x2/
- qcom-deb-images (debos recipes used for the base image): https://github.com/qualcomm-linux/qcom-deb-images
- Snapdragon X2 Linux software docs: https://docs.qualcomm.com/doc/SP80-A0399-4/topic/snapdragon-x2-linux-software-overview.html

## Firmware tooling
- qcom-firmware-extract (Debian): https://manpages.debian.org/unstable/qcom-firmware-extract/qcom-firmware-extract.8.en.html
- juergh/qcom-ath-board-update at `63b4f4e4dfbd5775b633429646289621434ab497` (ath12k board-2.bin encoder)
