#!/bin/sh
# Build Debian kernel packages for the UX3407NA from linux-msm/laptops-kernel 7.4-rc1
# plus the patches in this repo. Run inside the builder container (scripts/Dockerfile),
# with the qcom-deb-images checkout at $QCOM_DEB_IMAGES.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
src=${KERNEL_SRC:-/work/asus-linux74}
qcom=${QCOM_DEB_IMAGES:-/work/qcom-deb-images}
commit=23b349cb9eb1aefd226da1debd86011bdb86f57f
jobs=${JOBS:-$(nproc)}
cross=aarch64-linux-gnu-

if [ ! -d "$src" ]; then
    git init "$src"
    git -C "$src" remote add origin https://github.com/linux-msm/laptops-kernel.git
fi
if ! git -C "$src" cat-file -e "$commit^{commit}" 2>/dev/null; then
    git -C "$src" fetch --depth 1 origin "$commit"
fi
git -C "$src" checkout --detach "$commit"
git -C "$src" am "$repo"/patches/kernel/*.patch

cd "$src"
make -j"$jobs" ARCH=arm64 CROSS_COMPILE=$cross defconfig
ARCH=arm64 scripts/kconfig/merge_config.sh -m -r .config "$qcom"/kernel-configs/*.config "$repo"/config/kernel/a14-luks.config
# No debug-info packages; they are huge and not needed here.
scripts/config --disable DEBUG_INFO --disable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT --disable DEBUG_INFO_DWARF4 --disable DEBUG_INFO_DWARF5 --enable DEBUG_INFO_NONE
make -j"$jobs" ARCH=arm64 CROSS_COMPILE=$cross olddefconfig
grep -q '^CONFIG_DM_CRYPT=[ym]' .config
make -j"$jobs" ARCH=arm64 CROSS_COMPILE=$cross DEB_HOST_ARCH=arm64 bindeb-pkg
echo "Kernel packages: $(make -s ARCH=arm64 kernelrelease)"
