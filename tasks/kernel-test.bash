#!/usr/bin/env bash
# MSM kernel compilation testing
# Copyright (C) 2020 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

## Exit script on error
set -e

## Import common kernel script
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"/kernel-common

# Pre-hook
build_prehook() {
    for target in "${prima_enabled[@]}"; do
        [[ $target == "$config" ]] && WLAN=("CONFIG_PRONTO_WLAN=y")
        break
    done
    for target in "${qcacld_enabled[@]}"; do
        [[ $target == "$config" ]] && WLAN=("CONFIG_QCA_CLD_WLAN=y")
        # Just in case it's still SDXHEDGEHOG instead of SDX20
        [[ $target == sdx ]] && WLAN=("CONFIG_ARCH_SDXHEDGEHOG=y")
        break
    done

    echo "==== Testing ${1^^}: $config-perf_defconfig ===="
    rm -rf /tmp/build
    START_TIME=$(date +%s)
    make -sj"$CPUs" ARCH="$1" O=/tmp/build "$config"-perf_defconfig || return
    # override to disable qm215 on msm8937 targets
    [[ $KERNVER == 4.9 && $config =~ msm8937 ]] && scripts/config --file /tmp/build/.config -d ARCH_QM215
    export START_TIME WLAN
}

# Post-hook
build_posthook() {
    echo
    echo -n "Build done in $(show_duration)"
    if [[ -n $STATUS ]]; then
        echo " and ${BLD}failed$RST"
        exit "$STATUS"
    fi
    echo -e '\n'
    unset START_TIME WLAN
}

# Kernel repository
KERNVER=$VERSION.$PATCHLEVEL
MSM_KERNVER=msm-$KERNVER

# Kernel detection
case "$KERNVER" in
3.18)
    common_configs=(
        apq8053_IoE
        msm8937   # msm8917 / msm8937
        msmcortex # msm8953
    )
    arm32_configs=(
        mdm           # mdm9650 IoT
        mdm9607       # mdm9607 IoT
        mdm9607-128mb # mdm9607 IoT (128 MB)
        mdm9640       # mdm9640 IoT
        msm8909       # msm8909 Android Go
        msm8909w      # msm8909 Android Watch
        msm8909w-1gb  # msm8909 Android Watch (1 GB)
        sdx           # sdx20
    )
    arm64_configs=(
        msm      # msm8996
        msm-auto # msm8996 Android Auto
    )

    prima_enabled=(apq8053_IoE msm8909{,w{,-1gb}} msm8937 msmcortex)
    qcacld_enabled=(mdm mdm9607{,-128m} mdm9640 msm{,-auto} sdx)
    ;;
4.9)
    # Clang by default for this target
    CLANG=true
    common_configs=(
        msm8937 # sdm429 / sdm439 / qm215
        msm8953 # sdm450 / sdm632
        sdm670  # sdm710
    )
    arm32_configs=(
        mdm9607         # mdm9607 Wear OS
        msm8909         # msm8909 Android Go
        msm8909-minimal # msm8909 Android Go (minimal)
        msm8909w        # msm8909 Android Watch
        msm8937go       # sdm429 / sdm439 / qm215 Android Go
        msm8953-batcam  # msm8953-based batcam
        sa415m
        sdm429-bg    # sdw3300 Wear OS
        sdxpoorwills # sda845
        spyro        # spyro Wear OS
    )
    arm64_configs=(
        qcs605
        sdm845
    )

    prima_enabled=(msm8909{,w,-minimal} msm8937{,go} msm8953{,-batcam} sdm429-bg spyro)
    # msm8917 on 4.9 apparently also has one with qcacld instead of prima
    qcacld_enabled=(mdm9607 qcs605 sdm670 sdm845)
    ;;
*)
    # nothing to do
    exit
    ;;
esac

echo "==== Testing kernel: $MSM_KERNVER ===="
# Number of CPUs/Threads
CPUs=$(nproc --all)
# Clang
[[ -n $CLANG ]] && get_clang-ver 11

# ARM tasks
(
    # For the rest of the GCC if not Clang
    GCC_48=/opt/kud/android/arm-eabi-4.8
    # For compiler only
    GCC_49=/opt/kud/android/arm-linux-androideabi-4.9
    BIN=${CLANG:+$CLANG_PATH/bin:}$GCC_48/bin:$GCC_49/bin:$PATH
    LD=${CLANG:+$CLANG_PATH/lib:}$GCC_48/lib:$GCC_49/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    [[ -n $CLANG ]] && TARGETS=("CROSS_COMPILE=arm-linux-androideabi-" "CC=clang" "LD=arm-eabi-ld" "CLANG_TRIPLE=arm-linux-gnueabi") ||
        TARGETS=("CROSS_COMPILE=arm-eabi-" "CC=arm-linux-androideabi-gcc")

    for config in "${common_configs[@]}" "${arm32_configs[@]}"; do
        build_prehook arm || { echo && continue; }
        if [[ $KERNVER == 4.9 ]]; then
            # override to enable qm215 on msm8909 targets
            [[ $config =~ msm8909 ]] && scripts/config --file /tmp/build/.config -e ARCH_QM215
            # override to force disable techpack/audio
            [[ $config == msm8953-batcam ]] && sed -i 's/ARCH_MSM8953/ARCH_MSM8953_FALSE/g' techpack/audio/Makefile
        fi
        PATH=$BIN LD_LIBRARY_PATH=$LD \
            make -sj"$CPUs" ARCH=arm O=/tmp/build "${TARGETS[@]}" "${WLAN[@]}" \
            zImage-dtb modules || STATUS=$?
        # override to re-enable techpack/audio
        [[ $KERNVER == 4.9 && $config == msm8953-batcam ]] && sed -i 's/ARCH_MSM8953_FALSE/ARCH_MSM8953/g' techpack/audio/Makefile
        build_posthook
    done
)

# ARM64 tasks
(
    GCC=/opt/kud/android/aarch64-linux-android-4.9
    BIN=${CLANG:+$CLANG_PATH/bin:}$GCC/bin:$PATH
    LD=${CLANG:+$CLANG_PATH/lib:}$GCC/lib:$GCC/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    [[ -n $CLANG ]] && TARGETS=("CC=clang" "CLANG_TRIPLE=aarch64-linux-gnu") ||
        TARGETS=("CC=aarch64-linux-android-gcc")

    for config in "${common_configs[@]}" "${arm64_configs[@]}"; do
        build_prehook arm64 || { echo && continue; }
        PATH=$BIN LD_LIBRARY_PATH=$LD \
            make -sj"$CPUs" ARCH=arm64 O=/tmp/build CROSS_COMPILE=aarch64-linux-android- \
            "${TARGETS[@]}" "${WLAN[@]}" Image.gz-dtb modules || STATUS=$?
        build_posthook
    done
)
