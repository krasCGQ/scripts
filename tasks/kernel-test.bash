#!/usr/bin/env bash
# MSM kernel compilation testing
# Copyright (C) 2020 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

## Exit script on error
set -e

## Import common kernel script
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"/kernel-common

# Delete build folder upon exit
trap 'rm -rf $OUT' EXIT

# Pre-hook
build_prehook() {
    local BASE_CFG TARGET_CFG
    BASE_CFG=$(echo "$CONFIG" | cut -d',' -f1)
    TARGET_CFG=$(echo "$CONFIG" | cut -d',' -f2)

    echo -n "==== Testing ${1^^}: $BASE_CFG-perf_defconfig"
    [[ $BASE_CFG != "$TARGET_CFG" ]] && echo -n " - $TARGET_CFG target"
    echo " ===="
    START_TIME=$(date +%s)
    make -sj"$CPUs" ARCH="$1" O="$OUT" "$BASE_CFG"-perf_defconfig || return

    # override for msm8937 configs, to allow testing both msm8937 and qm215 targets
    if [[ $BASE_CFG =~ msm8937 ]]; then
        if [[ $TARGET_CFG == qm215 ]]; then
            # disable any other ARCHes
            scripts/config --file "$OUT"/.config \
                -d ARCH_MSM8917 -d ARCH_MSM8937 -d ARCH_MSM8940 -d ARCH_SDM429 -d ARCH_SDM439
        else
            # disable qm215
            scripts/config --file "$OUT"/.config -d ARCH_QM215
        fi
    fi
    # define WLAN targets
    for TARGET in "${PRIMA_ENABLED[@]}"; do
        if [[ $TARGET == "$BASE_CFG" ]]; then
            scripts/config --file "$OUT"/.config -e PRONTO_WLAN
            break
        fi
    done
    for TARGET in "${QCACLD_ENABLED[@]}"; do
        if [[ $TARGET == "$BASE_CFG" ]]; then
            # QCA_CLD_WLAN_PROFILE is set unconditionally; only supported on qcacld-3.0 5.2.x
            scripts/config --file "$OUT"/.config \
                -e QCA_CLD_WLAN --set-str QCA_CLD_WLAN_PROFILE default
            # just in case it's still SDXHEDGEHOG instead of SDX20
            [[ $TARGET == sdx ]] && WLAN=("CONFIG_ARCH_SDXHEDGEHOG=y")
            break
        fi
    done

    # export out from function
    export START_TIME WLAN
}

# Post-hook
build_posthook() {
    echo
    echo "Build completed in $(show_duration)"
    echo
    make -sj"$CPUs" ARCH="$1" O="$OUT" mrproper
    unset START_TIME WLAN
}

# Kernel repository
KERNVER=$VERSION.$PATCHLEVEL
MSM_KERNVER=msm-$KERNVER
# Build directory
OUT=/home/android-build/kernel-test

# Kernel detection
case "$KERNVER" in
3.18)
    COMMON_CONFIGS=(
        'apq8053_IoE'
        'msm8937'   # msm8917 / msm8937
        'msmcortex' # msm8953
    )
    ARM32_CONFIGS=(
        'mdm'           # mdm9650 IoT
        'mdm9607'       # mdm9607 IoT
        'mdm9607-128mb' # mdm9607 IoT (128 MB)
        'mdm9640'       # mdm9640 IoT
        'msm8909'       # msm8909 Android Go
        'msm8909w'      # msm8909 Android Watch
        'msm8909w-1gb'  # msm8909 Android Watch (1 GB)
        'sdx'           # sdx20
    )
    ARM64_CONFIGS=(
        'msm'      # msm8996
        'msm-auto' # msm8996 Android Auto
    )

    PRIMA_ENABLED=(apq8053_IoE msm8909{,w{,-1gb}} msm8937 msmcortex)
    QCACLD_ENABLED=(mdm mdm9607{,-128m} mdm9640 msm{,-auto} sdx)
    ;;
4.9)
    # Clang by default for this target
    [[ -z $CLANG ]] && CLANG=qti-10
    COMMON_CONFIGS=(
        'msm8937'       # sdm429 / sdm439 / qm215 - #1 8937 platform
        'msm8937,qm215' # sdm429 / sdm439 / qm215 - #2 8909 platform
        'msm8953'       # sdm450 / sdm632
        'sdm670'        # sdm710
    )
    ARM32_CONFIGS=(
        'mdm9607'         # mdm9607 Wear OS
        'msm8909'         # msm8909 Android Go
        'msm8909-minimal' # msm8909 Android Go (minimal)
        'msm8909w'        # msm8909 Android Watch
        'msm8937go'       # sdm429 / sdm439 / qm215 Android Go - #1 8937 platform
        'msm8937go,qm215' # sdm429 / sdm439 / qm215 Android Go - #2 8909 platform
        'msm8953-batcam'  # msm8953-based batcam
        'sa415m'
        'sdm429-bg'    # sdw3300 Wear OS
        'sdxpoorwills' # sda845
        'spyro'        # spyro Wear OS
    )
    ARM64_CONFIGS=(
        'qcs605'
        'sdm845'
    )

    PRIMA_ENABLED=(msm8909{,w,-minimal} msm8937{,go} msm8953 sdm429-bg spyro)
    # msm8917 on 4.9 apparently also has one with qcacld instead of prima
    QCACLD_ENABLED=(mdm9607 qcs605 sdm670 sdm845)
    ;;
*)
    # nothing to do
    exit
    ;;
esac

echo "==== Testing kernel: $MSM_KERNVER ===="
# Number of CPUs/Threads
CPUs=$(nproc --all)
# Path to Binutils
BINUTILS=/opt/kud/binutils
# Clang: Use CLANG=false to use GCC for targets that default to use Clang
[[ $CLANG == false ]] && unset CLANG
[[ -n $CLANG ]] && get_clang-ver "$CLANG"

# ARM tasks
(
    [[ -n $CUSTOM ]] && GCC=/opt/kud/linaro/gcc-arm-10.2-2020.11-x86_64-arm-none-linux-gnueabihf ||
        GCC=/opt/kud/android/arm-linux-androideabi-4.9
    BIN=${CLANG:+$CLANG_PATH/bin:}$BINUTILS/bin:$GCC/bin:$PATH
    LD=${CLANG:+$CLANG_PATH/lib:}$BINUTILS/lib:$GCC/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    TARGETS=("CROSS_COMPILE=arm-linux-gnueabi-")
    if [[ -n $CLANG ]]; then
        TARGETS+=("CC=clang")
    else
        [[ -n $CUSTOM ]] && TARGETS+=("CC=arm-none-linux-gnueabihf-gcc") ||
            TARGETS+=("CC=arm-linux-androideabi-gcc")
    fi
    TARGETS+=("DTC_EXT=dtc")

    for CONFIG in "${COMMON_CONFIGS[@]}" "${ARM32_CONFIGS[@]}"; do
        build_prehook arm || { echo && continue; }
        # override to disable audio-kernel for batcam targets
        [[ $KERNVER == 4.9 && $CONFIG == msm8953-batcam ]] &&
            sed -i 's/ARCH_MSM8953/ARCH_MSM8953_FALSE/g' techpack/audio/Makefile
        PATH=$BIN LD_LIBRARY_PATH=$LD \
            make -sj"$CPUs" ARCH=arm O=$OUT "${TARGETS[@]}" "${WLAN[@]}" \
            zImage-dtb modules
        if [[ $KERNVER == 4.9 ]]; then
            case $CONFIG in
            mdm9607 | msm8909 | msm8909w | msm8909-minimal | sa415m | sdxpoorwills) ;;
                # target doesn't have DTBOs
            *)
                PATH=$BIN LD_LIBRARY_PATH=$LD \
                    make -sj"$CPUs" ARCH=arm O=$OUT "${TARGETS[@]}" \
                    CONFIG_BUILD_ARM64_DT_OVERLAY=y dtbs
                ;;
            esac
            [[ $CONFIG == msm8953-batcam ]] &&
                sed -i 's/ARCH_MSM8953_FALSE/ARCH_MSM8953/g' techpack/audio/Makefile
        fi
        build_posthook arm
    done
)

# ARM64 tasks
(
    [[ -n $CUSTOM ]] && GCC=/opt/kud/linaro/gcc-arm-10.2-2020.11-x86_64-aarch64-none-linux-gnu ||
        GCC=/opt/kud/android/aarch64-linux-android-4.9
    BIN=${CLANG:+$CLANG_PATH/bin:}$BINUTILS/bin:$GCC/bin:$PATH
    LD=${CLANG:+$CLANG_PATH/lib:}$BINUTILS/lib:$GCC/lib:$GCC/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    TARGETS=("CROSS_COMPILE=aarch64-linux-gnu-")
    if [[ -n $CLANG ]]; then
        TARGETS+=("CC=clang")
    else
        [[ -n $CUSTOM ]] && TARGETS+=("CC=aarch64-none-linux-gnu-gcc") ||
            TARGETS+=("CC=aarch64-linux-android-gcc")
    fi
    TARGETS+=("DTC_EXT=dtc")

    for CONFIG in "${COMMON_CONFIGS[@]}" "${ARM64_CONFIGS[@]}"; do
        build_prehook arm64 || { echo && continue; }
        PATH=$BIN LD_LIBRARY_PATH=$LD \
            make -sj"$CPUs" ARCH=arm64 O=$OUT "${TARGETS[@]}" "${WLAN[@]}" \
            Image.gz-dtb modules
        [[ $KERNVER == 4.9 ]] && PATH=$BIN LD_LIBRARY_PATH=$LD \
            make -sj"$CPUs" ARCH=arm64 O=$OUT "${TARGETS[@]}" \
            CONFIG_BUILD_ARM64_DT_OVERLAY=y dtbs
        build_posthook arm64
    done
)
