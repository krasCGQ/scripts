#!/usr/bin/env bash
# MSM kernel compilation testing
# Copyright (C) 2020 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

# Idea stolen from scripts/patch-kernel
# shellcheck disable=SC1090
source <(grep -E '^(VERSION|PATCHLEVEL)' Makefile | sed -e s/[[:space:]]//g)
MSM_KERNVER=msm-$VERSION.$PATCHLEVEL

case "${MSM_KERNVER/*-}" in
    3.18)
        echo "==== Testing kernel: $MSM_KERNVER ===="
        arm32_configs=(
            msm8909      # msm8909 Android Go
            msm8909w     # msm8909 Android Watch
            msm8909w-1gb # msm8909 Android Watch (1 GB)
            msm8937      # msm8917 / msm8937
            msmcortex    # msm8953
            sdx          # sdx20
        )

        arm64_configs=(
            msm8937     # msm8917 / msm8937
            msmcortex   # msm8953
            msm         # msm8996
            msm-auto    # msm8996 Android Auto
        ) ;;
    4.9)
        echo "==== Testing kernel: $MSM_KERNVER ===="
        CLANG=true
        arm32_configs=(
            msm8909         # msm8909 Android Go
            msm8909-minimal # msm8909 Android Go (minimal)
            msm8909w        # msm8909 Android Watch
            msm8937         # sdm429 / sdm439 / qm215
            msm8937go       # sdm429 / sdm439 / qm215 Android Go
            msm8953         # sdm450 / sdm632
            msm8953-batcam  # sdm450 / sdm632 with batcam (?)
            sa415m
            sdm429-bg       # sdm429 with G-Link BGCOM Transport
            sdm670          # sdm710
            sdxpoorwills    # sda845
        )
        arm64_configs=(
            msm8937     # sdm429 / sdm439 / qm215
            msm8953     # sdm450 / sdm632
            qcs605
            sdm670      # sdm710
            sdm845
        ) ;;
    *)
        # nothing to do
        exit ;;
esac

# Number of CPUs/Threads
CPUs=$(nproc --all)
# Clang
[[ -n $CLANG ]] && LLVM=/opt/kud/android/clang-r377782c

# ARM tasks
(
    # For the rest of the GCC if not Clang
    GCC_48=/opt/kud/android/arm-eabi-4.8
    # For compiler only
    GCC_49=/opt/kud/android/arm-linux-androideabi-4.9
    BIN=${CLANG:+$LLVM/bin:}$GCC_48/bin:$GCC_49/bin:$PATH
    LD=${CLANG:+$LLVM/lib:}$GCC_48/lib:$GCC_49/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    [[ -n $CLANG ]] && TARGETS=( "CROSS_COMPILE=arm-linux-androideabi-" "CC=clang" "LD=arm-eabi-ld" "CLANG_TRIPLE=arm-linux-gnueabi" ) \
                    || TARGETS=( "CROSS_COMPILE=arm-eabi-" "CC=arm-linux-androideabi-gcc" )

    for arm32_config in "${arm32_configs[@]}"; do
        echo "==== Testing ARM: $arm32_config-perf_defconfig ===="
        rm -rf /tmp/build
        make -sj"$CPUs" ARCH=arm O=/tmp/build "$arm32_config"-perf_defconfig
        time PATH=$BIN LD_LIBRARY_PATH=$LD \
            make -sj"$CPUs" ARCH=arm O=/tmp/build "${TARGETS[@]}" \
                            zImage-dtb modules || exit $?
        echo
    done
) || exit $?

# ARM64 tasks
(
    GCC=/opt/kud/android/aarch64-linux-android-4.9
    BIN=${CLANG:+$LLVM/bin:}$GCC/bin:$PATH
    LD=${CLANG:+$LLVM/lib:}$GCC/lib:$GCC/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    [[ -n $CLANG ]] && TARGETS=( "CC=clang" "CLANG_TRIPLE=aarch64-linux-gnu" ) \
                    || TARGETS=( "CC=aarch64-linux-android-gcc" )

    for arm64_config in "${arm64_configs[@]}"; do
        echo "==== Testing ARM64: $arm64_config-perf_defconfig ===="
        rm -rf /tmp/build
        make -sj"$CPUs" ARCH=arm64 O=/tmp/build "$arm64_config"-perf_defconfig
        time PATH=$BIN LD_LIBRARY_PATH=$LD \
            make -sj"$CPUs" ARCH=arm64 O=/tmp/build CROSS_COMPILE=aarch64-linux-android- \
                            "${TARGETS[@]}" Image.gz-dtb modules || exit $?
        echo
    done
) || exit $?
