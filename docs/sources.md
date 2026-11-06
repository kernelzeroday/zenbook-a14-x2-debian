# Sources

## Kernel and device tree
- linux-msm laptops kernel (qcom-laptops branch), 7.4-rc1, pinned commit `23b349cb9eb1aefd226da1debd86011bdb86f57f`:
  https://github.com/linux-msm/laptops-kernel
- Phoronix, "Linux 7.4 To Upstream Support For Three Snapdragon X2 Elite Laptops":
  https://www.phoronix.com/news/ASUS-UX3407NA-Linux-7.4
- UX3407NA DTS series on linux-arm-msm ("[PATCH 0/3] arm64: dts: qcom: Introduce Asus Zenbook A14 (UX3407NA)"):
  https://ratatoskr.run/linux-arm-msm/2026/06/17163526/t
- `drivers/gpu/drm/msm/adreno/a8xx_gpu.c`: zap shader / `SECVID_TRUST_CNTL` fallback
- `arch/arm64/boot/dts/qcom/hamoa.dtsi`: reference zap-shader node for X1E

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
