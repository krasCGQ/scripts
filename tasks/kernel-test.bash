#!/usr/bin/env bash
# MSM kernel compilation testing
# Copyright (C) 2020 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

## Import common kernel script
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"/kernel-common

# Exit script on error
set -e

# Idea stolen from scripts/patch-kernel
# shellcheck disable=SC1090
source <(grep -E '^(VERSION|PATCHLEVEL)' Makefile | sed -e s/[[:space:]]//g)
MSM_KERNVER=msm-$VERSION.$PATCHLEVEL

case "${MSM_KERNVER/*-}" in
    3.18)
        echo "==== Testing kernel: $MSM_KERNVER ===="
        arm32_configs=(
            apq8053_IoE
            mdm           # mdm9650 IoT
            mdm9607       # mdm9607 IoT
            mdm9607-128mb # mdm9607 IoT (128 MB)
            mdm9640       # mdm9640 IoT
            msm8909       # msm8909 Android Go
            msm8909w      # msm8909 Android Watch
            msm8909w-1gb  # msm8909 Android Watch (1 GB)
            msm8937       # msm8917 / msm8937
            msmcortex     # msm8953
            sdx           # sdx20
        )

        arm64_configs=(
            apq8053_IoE
            msm8937     # msm8917 / msm8937
            msmcortex   # msm8953
            msm         # msm8996
            msm-auto    # msm8996 Android Auto
        )

        prima_enabled=( apq8053_IoE msm8909 msm8909w msm8909w-1gb msm8937 msmcortex )
        qcacld_enabled=( mdm mdm9607 mdm9607-128m mdm9640 msm sdx ) ;;
    4.9)
        echo "==== Testing kernel: $MSM_KERNVER ===="
        CLANG=true
        arm32_configs=(
            mdm9607         # mdm9607 Wear OS
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
            spyro           # spyro Wear OS
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
[[ -n $CLANG ]] && get_clang-ver 10

# ARM tasks
(
    # For the rest of the GCC if not Clang
    GCC_48=/opt/kud/android/arm-eabi-4.8
    # For compiler only
    GCC_49=/opt/kud/android/arm-linux-androideabi-4.9
    BIN=${CLANG:+$CLANG_PATH:}$GCC_48/bin:$GCC_49/bin:$PATH
    LD=${CLANG:+${CLANG_PATH/bin/lib}:}$GCC_48/lib:$GCC_49/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    [[ -n $CLANG ]] && TARGETS=( "CROSS_COMPILE=arm-linux-androideabi-" "CC=clang" "LD=arm-eabi-ld" "CLANG_TRIPLE=arm-linux-gnueabi" ) \
                    || TARGETS=( "CROSS_COMPILE=arm-eabi-" "CC=arm-linux-androideabi-gcc" )

    for arm32_config in "${arm32_configs[@]}"; do
        for target in "${prima_enabled[@]}"; do
            [[ $target == "$arm32_config" ]] && WLAN=( "CONFIG_PRONTO_WLAN=y" )
            break
        done
        for target in "${qcacld_enabled[@]}"; do
            [[ $target == "$arm32_config" ]] && WLAN=( "CONFIG_QCA_CLD_WLAN=y" )
            # Just in case it's still SDXHEDGEHOG instead of SDX20
            [[ $target == sdx ]] && WLAN=( "CONFIG_ARCH_SDXHEDGEHOG=y" )
            break
        done

        echo "==== Testing ARM: $arm32_config-perf_defconfig ===="
        rm -rf /tmp/build
        START_TIME=$(date +%s)
        make -sj"$CPUs" ARCH=arm O=/tmp/build "$arm32_config"-perf_defconfig
        PATH=$BIN LD_LIBRARY_PATH=$LD \
        make -sj"$CPUs" ARCH=arm O=/tmp/build "${TARGETS[@]}" "${WLAN[@]}" \
                        zImage-dtb modules || STATUS=$?
        echo
        echo -n "Build done in $(show_duration)"
        if [[ -n $STATUS ]]; then
            echo " and ${BLD}failed$RST"
            exit $STATUS
        fi
        echo -e '\n'
        unset WLAN
    done
)

# ARM64 tasks
(
    GCC=/opt/kud/android/aarch64-linux-android-4.9
    BIN=${CLANG:+$CLANG_PATH:}$GCC/bin:$PATH
    LD=${CLANG:+${CLANG_PATH/bin/lib}:}$GCC/lib:$GCC/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    [[ -n $CLANG ]] && TARGETS=( "CC=clang" "CLANG_TRIPLE=aarch64-linux-gnu" ) \
                    || TARGETS=( "CC=aarch64-linux-android-gcc" )

    for arm64_config in "${arm64_configs[@]}"; do
        for target in "${prima_enabled[@]}"; do
            [[ $target == "$arm64_config" ]] && WLAN=( "CONFIG_PRONTO_WLAN=y" )
            break
        done
        for target in "${qcacld_enabled[@]}"; do
            [[ $target == "$arm64_config" ]] && WLAN=( "CONFIG_QCA_CLD_WLAN=y" )
            break
        done

        echo "==== Testing ARM64: $arm64_config-perf_defconfig ===="
        rm -rf /tmp/build
        # shellcheck disable=SC2034
        START_TIME=$(date +%s)
        make -sj"$CPUs" ARCH=arm64 O=/tmp/build "$arm64_config"-perf_defconfig
        PATH=$BIN LD_LIBRARY_PATH=$LD \
        make -sj"$CPUs" ARCH=arm64 O=/tmp/build CROSS_COMPILE=aarch64-linux-android- \
                        "${TARGETS[@]}" "${WLAN[@]}" Image.gz-dtb modules || STATUS=$?
        echo
        echo -n "Build done in $(show_duration)"
        if [[ -n $STATUS ]]; then
            echo " and ${BLD}failed$RST"
            exit $STATUS
        fi
        echo -e '\n'
        unset WLAN
    done
)
