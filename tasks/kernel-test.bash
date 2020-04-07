#!/usr/bin/env bash
# MSM kernel compilation testing
# Copyright (C) 2020 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

# Idea stolen from scripts/patch-kernel
# shellcheck disable=SC1090
source <(grep -E '^(VERSION|PATCHLEVEL)' Makefile | sed -e s/[[:space:]]//g)
MSM_KERNVER=msm-$VERSION.$PATCHLEVEL

if [[ $MSM_KERNVER =~ 3.18 ]]; then
    echo "==== Testing kernel: $MSM_KERNVER ===="
    arm32_configs=(
        msm8909     # msm8909 Android Go
        msm8909w    # msm8909 Android Watch
        msm8909w    # msm8909 Android Watch (1 GB)
        msm8937     # msm8917 / msm8937
        msmcortex   # msm8953
        sdx         # sdx20
    )

    arm64_configs=(
        msm8937     # msm8917 / msm8937
        msmcortex   # msm8953
        msm         # msm8996
        msm-auto    # msm8996 Android Auto
    )
else
    # nothing to do
    exit
fi

# Number of CPUs/Threads
CPUs=$(nproc --all)

# ARM tasks
(
    trap 'exit $?' ERR

    # For the rest of the GCC
    GCC_48=/opt/kud/android/arm-eabi-4.8
    # For compiler only
    GCC_49=/opt/kud/android/arm-linux-androideabi-4.9
    BIN=$GCC_48/bin:$GCC_49/bin:$PATH
    LD=$GCC_48/lib:$GCC_49/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

    for arm32_config in "${arm32_configs[@]}"; do
        echo "==== Testing ARM: $arm32_config-perf_defconfig ===="
        rm -rf /tmp/build
        make -sj"$CPUs" ARCH=arm O=/tmp/build "$arm32_config"-perf_defconfig
        time PATH=$BIN LD_LIBRARY_PATH=$LD \
            make -sj"$CPUs" ARCH=arm O=/tmp/build CROSS_COMPILE=arm-eabi- \
                            CC=arm-linux-androideabi-gcc \
                            zImage-dtb modules
        echo
    done
) || exit $?

# ARM64 tasks
(
    trap 'exit $?' ERR

    GCC=/opt/kud/android/aarch64-linux-android-4.9
    BIN=$GCC/bin:$PATH
    LD=$GCC/lib:$GCC/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}


    for arm64_config in "${arm64_configs[@]}"; do
        echo "==== Testing ARM64: $arm64_config-perf_defconfig ===="
        rm -rf /tmp/build
        make -sj"$CPUs" ARCH=arm64 O=/tmp/build "$arm64_config"-perf_defconfig
        time PATH=$BIN LD_LIBRARY_PATH=$LD \
            make -sj"$CPUs" ARCH=arm64 O=/tmp/build \
                            CROSS_COMPILE=aarch64-linux-androidkernel- \
                            Image.gz-dtb modules
        echo
    done
) || exit $?
