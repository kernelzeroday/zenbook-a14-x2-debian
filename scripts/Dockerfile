FROM ghcr.io/go-debos/debos@sha256:cba84885e2ac52a0e264553ba7ce72bb5c9fddf5623e1533bcec3b49d54d7066
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    debian-archive-keyring debos file make mmdebstrap mtools \
    python3-pexpect python3-pytest python3-defusedxml \
    qemu-efi-aarch64 qemu-system-arm xmlstarlet device-tree-compiler u-boot-tools \
    git build-essential crossbuild-essential-arm64 flex bison bc libdw-dev libelf-dev \
    libssl-dev dpkg-dev debhelper kmod python3 rsync coreutils \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /recipes
