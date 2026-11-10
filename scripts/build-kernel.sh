#!/bin/sh
# Build Debian kernel packages for the UX3407NA from *vanilla* Linux (torvalds) plus the
# patches in this repo. Works natively on the laptop or cross-compiled (CROSS_COMPILE=...).
#
#   KERNEL_TAG       upstream tag to build (default v7.4-rc2)
#   KERNEL_SRC       where to clone / reuse the source (default ~/code/linux-vanilla)
#   BUILD_DIR        out-of-tree build dir; the .debs land in its parent (default ~/code/zen-build/out-<tag>)
#   BASE_CONFIG      start from this config instead of defconfig + fragments
#                    (e.g. /proc/config.gz of a kernel that already works on this laptop)
#   QCOM_DEB_IMAGES  qcom-deb-images checkout for kernel-configs/*.config (when no BASE_CONFIG)
#   JOBS             parallel jobs (default 6)
#   GUARD=0          do not wrap make in scripts/guarded-make.sh
#
# On the laptop itself: run `scripts/cpu low` first. Sustained all-core load at full clocks
# powers the machine off at firmware level (see docs/gotchas.md). guarded-make.sh pins the
# build to cluster 0, nices it, and pauses it when hot or when the frequency cap is lost.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
tag=${KERNEL_TAG:-v7.4-rc2}
src=${KERNEL_SRC:-$HOME/code/linux-vanilla}
out=${BUILD_DIR:-$HOME/code/zen-build/out-$tag}
jobs=${JOBS:-6}
cross=${CROSS_COMPILE:-}
branch=a14-$tag

if [ ! -d "$src/.git" ]; then
    git clone --depth 1 --branch "$tag" https://github.com/torvalds/linux.git "$src"
fi
git -C "$src" fetch --depth 1 origin tag "$tag" 2>/dev/null || :
git -C "$src" switch -C "$branch" "$tag^{commit}"
git -C "$src" am "$repo"/patches/kernel/*.patch

mkdir -p "$out"
mk() { make -C "$src" O="$out" ARCH=arm64 ${cross:+CROSS_COMPILE=$cross} "$@"; }

if [ -n "${BASE_CONFIG:-}" ]; then
    case $BASE_CONFIG in *.gz) zcat "$BASE_CONFIG" ;; *) cat "$BASE_CONFIG" ;; esac > "$out/.config"
    "$src"/scripts/kconfig/merge_config.sh -m -O "$out" "$out/.config" "$repo"/config/kernel/a14-luks.config
else
    qcom=${QCOM_DEB_IMAGES:?set QCOM_DEB_IMAGES or BASE_CONFIG}
    mk defconfig
    ARCH=arm64 "$src"/scripts/kconfig/merge_config.sh -m -O "$out" "$out/.config" \
        "$qcom"/kernel-configs/*.config "$repo"/config/kernel/a14-luks.config
fi
# No debug-info packages; they are huge and not needed here.
"$src"/scripts/config --file "$out/.config" --disable DEBUG_INFO \
    --disable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT --disable DEBUG_INFO_DWARF4 \
    --disable DEBUG_INFO_DWARF5 --enable DEBUG_INFO_NONE
mk olddefconfig
grep -q '^CONFIG_DM_CRYPT=[ym]' "$out/.config"

if [ "${GUARD:-1}" = 1 ]; then
    (cd "$src" && "$repo"/scripts/guarded-make.sh "$out/../logs-$tag" O="$out" ARCH=arm64 \
        ${cross:+CROSS_COMPILE=$cross} -j"$jobs" DEB_HOST_ARCH=arm64 bindeb-pkg)
else
    mk -j"$jobs" DEB_HOST_ARCH=arm64 bindeb-pkg
fi
echo "Kernel packages for $(mk -s kernelrelease) in $(dirname "$out")"
