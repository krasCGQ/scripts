#!/usr/bin/env bash
# shellcheck source=/dev/null
# KudProject kernel build tasks
# Copyright (C) 2018-2021 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

# Use SCHED_BATCH for the entire process
chrt -abp 0 $$

TASKS_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# Import common kernel script
. "$TASKS_DIR"/kernel-common
# Import MoeSyndrome-specific tasks
. "$TASKS_DIR"/kernel-release

## Functions

# For any errors, no matter what, post error notification and exit script
tgError() {
    # make SIGINT no-op to avoid double-posting
    trap ' ' INT
    tgNotify fail
    exit "${STATUS:-1}"
}

# Prints message to stderr and exit script, OR call tgError function
die() {
    [[ -z $STATUS && -n $STARTED ]] && STATUS=$?
    prWarn "$1"
    [[ -n $STARTED ]] && tgError || exit 1
}

# Whenever script fails, save exit status and run tgError
trap '[[ -n $STARTED ]] && STATUS=$?; tgError' ERR
# In case of signal interrupt, post interruption notification and exit script
trap '[[ -n $STARTED ]] && tgNotify interrupt; exit 130' INT
# Wait every process before exit
trap 'wait' EXIT

## Parse parameters

parseParams() {
    [[ $# -eq 0 ]] && die "No parameter specified!"
    while [[ $# -ge 1 ]]; do
        case $1 in
        # REQUIRED
        -d | --device)
            shift
            # Supported devices:
            case ${1,,} in
            grus | sirius)
                DEVICE=${1,,}
                PAGE_SIZE=4096
                ;;
            mido)
                DEVICE=${1,,}
                ;;
            scale)
                DEVICE=${1,,}
                IS_32BIT=true
                NEEDS_DT_IMG=true
                PAGE_SIZE=2048
                ;;
            x00t)
                DEVICE=${1^^}
                ;;
            *)
                die "Invalid device specified!"
                ;;
            esac
            ;;

        # OPTIONAL
        -b | --build-only)
            # Overrides incompatible `-u | --upload`
            TASK_TYPE=build-only
            ;;
        -c | --clang)
            COMPILER=clang
            ;;
        --clean)
            # Overrides incompatible `--dirty`
            BUILD_TYPE=clean
            ;;
        -cv | --clang-version)
            shift
            # Supported Clang corresponding to function in kernel-common
            get_clang-ver "$1"
            ;;
        --debug)
            # Assume section mismatch(es) debugging as a target
            TARGETS+=("CONFIG_DEBUG_SECTION_MISMATCH=y")
            ;;
        --dirty)
            # Overrides incompatible `--clean`
            BUILD_TYPE=dirty
            ;;
        --external-dtc)
            # This has no effect on sources without or has DTC_EXT removed
            TARGETS+=("DTC_EXT=$(command -v dtc || die "System DTC doesn't exist!")")
            ;;
        --no-announce)
            NO_ANNOUNCE=true
            ;;
        -s | --stock)
            STOCK=true
            ;;
        --sign)
            # Automatically done with release build
            SIGN_BUILD=true
            ;;

        # OPTIONAL, REQUIRES RELEASE SCRIPT SOURCED
        -j | --json)
            # Ignored if we're not releasing build
            [[ -n $RELEASE_SOURCED ]] && GENERATE_JSON=true
            ;;
        -u | --upload)
            shift
            # Overrides incompatible `-b | --build-only`
            if [[ -n $RELEASE_SOURCED ]]; then
                TASK_TYPE=upload
                case $1 in
                ci) UPLOAD_TYPE=ci ;;
                release)
                    SIGN_BUILD=true
                    UPLOAD_TYPE=release
                    ;;
                *) prWarn "\"$1\" is invalid upload type. Skipping." ;;
                esac
                [[ -n $UPLOAD_TYPE ]] && export UPLOAD_TYPE
            fi
            ;;

        # Unsupported parameter, skip
        *)
            prWarn "Unrecognized parameter specified: \"$1\""
            ;;
        esac
        shift
    done
}

# Unset the following parameters just in case
unset LIB_PATHs TARGETS
# Assume GCC by default, will be overridden by parseParams() below
COMPILER=gcc
parseParams "$@"

# Import announcement-specific tasks
. "$TASKS_DIR"/kernel-announce
# Make '**' recursive
shopt -s globstar

## Variables

# Paths
ROOT_DIR=$HOME/KudProject
OPT_DIR=/opt/kud
# Number of threads used
THREADS=$(nproc --all)
# FIXME: Find a way to reverse this; introduce a variable for now
[[ $COMPILER == clang && -z $STOCK ]] && CLANG_CUSTOM=true

# Binutils (standalone, unified)
BINUTILS=$OPT_DIR/binutils
if [[ -z $IS_32BIT ]]; then
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_ARM32=arm-linux-gnueabi-
else
    CROSS_COMPILE=arm-linux-gnueabi-
fi
BINs=("${CROSS_COMPILE}"ld ${CROSS_COMPILE_ARM32:+"${CROSS_COMPILE_ARM32}"ld})
# Custom Clang compiler (if used)
# Refer to llvm-proton-bin on AUR: https://aur.archlinux.org/packages/llvm-proton-bin
[[ -n $CLANG_CUSTOM ]] && CLANG_PATH=/opt/proton-clang
# Clang: Pass compiler of choice to CC
[[ $COMPILER == clang ]] && CC=$COMPILER
# GCC compiler
if [[ $COMPILER == gcc ]]; then
    if [[ -z $STOCK ]]; then
        # GNU-A version
        GNUA_VERSION=gcc-arm-10.2-2020.11-x86_64
        # Aarch64 toolchain
        GCC_64BIT=linaro/$GNUA_VERSION-aarch64-none-linux-gnu
        GCC_64BIN=${GCC_64BIT/linaro\/$GNUA_VERSION-/}-$COMPILER
        # Aarch32 toolchain, required for compat vDSO on ARM64 devices
        GCC_32BIT=linaro/$GNUA_VERSION-arm-none-linux-gnueabihf
        GCC_32BIN=${GCC_32BIT/linaro\/$GNUA_VERSION-/}-$COMPILER
    else
        # Aarch64 toolchain
        GCC_64BIT=android/aarch64-linux-android-4.9
        GCC_64BIN=${GCC_64BIT/android\//}
        GCC_64BIN=${GCC_64BIN/4.9/$COMPILER}
        # Aarch32 toolchain, required for compat vDSO on ARM64 devices
        GCC_32BIT=android/arm-linux-androideabi-4.9
        GCC_32BIN=${GCC_32BIT/android\//}
        GCC_32BIN=${GCC_32BIN/4.9/$COMPILER}
    fi
    # Aarch64 toolchain
    GCC_64BIT=$OPT_DIR/$GCC_64BIT
    [[ -z $IS_32BIT ]] && BINs+=("$GCC_64BIN")
    # Aarch32 toolchain, required for compat vDSO on ARM64 devices
    GCC_32BIT=$OPT_DIR/$GCC_32BIT
    BINs+=("$GCC_32BIN")
    # Pass compiler of choice to CC
    [[ -n $IS_32BIT ]] && CC=$GCC_32BIN || CC=$GCC_64BIN
    # CC_ARM32 variable here is placeholder
    [[ -z $IS_32BIT && $COMPILER != clang ]] && CC_ARM32=true
fi

# Set compiler PATHs and LD_LIBRARY_PATHs here to be used later while building
if [[ $COMPILER == clang ]]; then
    TC_PATHs=$CLANG_PATH/bin
    # Include lib64 for AOSP Clang
    LD_PATHs=$CLANG_PATH/lib${STOCK:+:$CLANG_PATH/lib64}
else
    TC_PATHs=$GCC_64BIT/bin:$GCC_32BIT/bin
    LD_PATHs=$GCC_64BIT/lib:$GCC_32BIT/lib
fi
# Not exported; will be passed to make instead
PATH=$BINUTILS/bin:$TC_PATHs:$PATH
export LD_LIBRARY_PATH=$BINUTILS/lib:$LD_PATHs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

# Kernel build variables
AK=$ROOT_DIR/AnyKernel/$DEVICE
BRANCH=$(git rev-parse --abbrev-ref HEAD)
# Kernel branding: Use branch name if returned undefined
setBranding 2>/dev/null || NAME=$BRANCH
# Set required ARCH, kernel name
if [[ -z $IS_32BIT ]]; then
    ARCH=arm64
    IMAGE_NAME=Image.gz
else
    ARCH=arm
    IMAGE_NAME=zImage
fi
OUT=/home/android-build/kernels/$DEVICE
OUT_KERNEL=$OUT/arch/$ARCH/boot

## Commands

# Sanity checks
prInfo "Running sanity checks..."
sleep 1

# Missing device choice
[[ -z $DEVICE ]] && die "Please specify target device."
# Requested to use non-custom Clang, but desired version isn't specified
[[ $COMPILER == clang && -z $CLANG_VERSION && -n $STOCK ]] && die "Please specify non-custom Clang version to use."
# Missing any build components (excluding Clang, since it's already checked on get_clang-ver())
for BIN in "${BINs[@]}"; do
    PATH=$BINUTILS/bin:$TC_PATHs command -v "$BIN" >/dev/null || die "$BLD$(basename "$BIN")$RST doesn't exist in defined path."
done
# Unset when done
unset BINs
# It's not a build-only task, but missing device's AnyKernel resource
[[ $TASK_TYPE != build-only && ! -d $AK ]] && die "$BLD$(basename "$AK")$RST doesn't exist in defined path."
# CAF's gcc-wrapper.py is written in Python 2, but MSM kernels <= 3.10 doesn't
# call python2 directly without a patch from newer kernels; we have to utilize
# virtualenv2 for such kernels.
if chkKernel 3.10 && [[ -f scripts/gcc-wrapper.py ]] && grep -q gcc-wrapper.py Makefile; then
    . $OPT_DIR/venv2/bin/activate || prWarn "virtualenv2 can't be sourced. Build may fail."
fi

# Script beginning
prInfo "Starting build script..."
tgNotify start
sleep 1

# Clean build directory
if [[ $BUILD_TYPE != dirty && -d $OUT ]]; then
    prInfo "Cleaning build directory..."
    if [[ $BUILD_TYPE != clean ]]; then
        make -s ARCH=$ARCH O="$OUT" clean 2>/dev/null
        # Delete earlier dt{,bo}.img created by this build script
        rm -f "$OUT_KERNEL"/dts/dt{,bo}.img
    else
        # Remove out folder instead of doing mrproper/distclean
        rm -r "$OUT"
    fi
fi

# Linux kernel < 3.15 doesn't automatically create out folder without an upstream
# patch. We have to do this manually otherwise such kernel will cause an error.
chkKernel 3.14 && [[ ! -d $OUT ]] && mkdir -p "$OUT"

# Regenerate config for source changes when required
if [[ -f $OUT/.config ]]; then
    prInfo "Regenerating config for source changes..."
    make -s ARCH=$ARCH O="$OUT" oldconfig
# However, if config file doesn't exist, generate a fresh config
else
    prInfo "Generating a new config..."
    read -rp "  Input a defconfig name (without '_defconfig'): " DEFCONFIG
    # If defconfig name is empty, assume device name as defconfig name instead
    [[ -z $DEFCONFIG ]] && DEFCONFIG=$DEVICE
    make -j"$THREADS" -s ARCH=$ARCH O="$OUT" "${DEFCONFIG}"_defconfig
fi

# Announce build information; only pass as minimum as possible make variables
if [[ -z $NO_ANNOUNCE || -n $GENERATE_JSON ]]; then
    UTS_RELEASE=$(PATH=$PATH make -s ARCH=$ARCH O="$OUT" CROSS_COMPILE_ARM32=$CROSS_COMPILE_ARM32 \
        CC=$CC ${CC_ARM32:+CC_ARM32=$GCC_32BIN} kernelrelease 2>/dev/null | tail -1)
    export UTS_RELEASE
fi
tgNotify info

# Only execute modules build if it's explicitly needed
grep -q '=m' "$OUT"/.config && HAS_MODULES=true
# Whether target needs DTBO
grep -q 'BUILD_ARM64_DT_OVERLAY=y' "$OUT"/.config && NEEDS_DTBO=true

# Let's build the kernel!
prInfo "Building kernel${HAS_MODULES:+ and modules}..."
# Export timestamp earlier before build
KBUILD_BUILD_TIMESTAMP="$(date)"
export KBUILD_BUILD_TIMESTAMP
PATH=$PATH \
    make -j"$THREADS" -s ARCH=$ARCH O="$OUT" CROSS_COMPILE=$CROSS_COMPILE \
    CROSS_COMPILE_ARM32=$CROSS_COMPILE_ARM32 CC=$CC ${CC_ARM32:+CC_ARM32=$GCC_32BIN} \
    "${TARGETS[@]}" ${IS_32BIT:+z}Image dtbs ${HAS_MODULES:+modules}

# Build dt.img and/or dtbo.img if needed
if [[ -n $NEEDS_DT_IMG ]]; then
    prInfo "Creating dt.img..."
    "$SCRIPT_DIR"/prebuilts/bin/dtbToolLineage -s $PAGE_SIZE \
        -o "$OUT_KERNEL"/dts/dt.img -p "$OUT"/scripts/dtc/ "$OUT_KERNEL"/dts/ >/dev/null
fi
if [[ -n $NEEDS_DTBO ]]; then
    prInfo "Creating dtbo.img..."
    python2 "$SCRIPT_DIR"/modules/libufdt/utils/src/mkdtboimg.py create \
        "$OUT_KERNEL"/dts/dtbo.img --page_size=$PAGE_SIZE \
        "$OUT_KERNEL"/dts/**/*.dtbo
fi

if [[ $TASK_TYPE != build-only ]]; then
    prInfo "Cleaning AnyKernel folder..."
    # Clean everything except zip files
    git -C "$AK" clean -qdfx -e '*.zip'

    prInfo "Copying kernel image and devicetree..."
    # ARM64: Compress resulting kernel image with fastest compression
    [[ -z $IS_32BIT ]] && pigz -f9 "$OUT_KERNEL"/Image
    if [[ -n $NEEDS_DT_IMG ]]; then
        # Copy compressed kernel image and dt.img
        cp "$OUT_KERNEL"/$IMAGE_NAME "$AK"
        cp "$OUT_KERNEL"/dts/dt.img "$AK"
    else
        # Append dtbs to compressed kernel image and copy
        cat "$OUT_KERNEL"/$IMAGE_NAME "$OUT_KERNEL"/dts/**/*.dtb >"$AK"/$IMAGE_NAME-dtb
    fi
    # Copy dtbo.img for supported devices
    [[ -n $NEEDS_DTBO ]] && cp "$OUT_KERNEL"/dts/dtbo.img "$AK"

    if [[ -n $HAS_MODULES ]]; then
        # Strip kernel modules
        prInfo "Stripping kernel modules..."
        for MODULE in "$OUT"/**/*.ko; do
            PATH=$PATH ${CROSS_COMPILE}strip -g "$MODULE"
        done

        # Copy kernel modules
        prInfo "Copying kernel modules..."
        . <(grep CONFIG_MODULE_SIG_HASH "$OUT"/.config)
        mkdir -p "$AK"/modules/vendor/lib/modules
        for MODULE in "$OUT"/**/*.ko; do
            if [[ -n $CONFIG_MODULE_SIG_HASH ]]; then
                "$OUT"/scripts/sign-file "$CONFIG_MODULE_SIG_HASH" \
                    "$OUT"/certs/signing_key.{pem,x509} "$MODULE" \
                    "$AK"/modules/vendor/lib/modules/"$(basename "$MODULE")"
            else
                cp "$MODULE" "$AK"/modules/vendor/lib/modules
            fi
        done
    fi

    # Make flashable kernel zip
    ZIP=$NAME-$DEVICE-$(date +%Y%m%d-%H%M)${SIGN_BUILD:+-unsigned}.zip
    prInfo "Creating $ZIP..."
    (
        # Unlikely to fail; but we have to define this way to satisfy shellcheck
        cd "$AK" || die "$BLD$(basename "$AK")$RST doesn't exist in defined path."

        # Create with p7zip, excluding README and any other zip
        # Store kernel image uncompressed, however
        7za a -bso0 -mx=9 -mpass=15 -mmt="$THREADS" "$ZIP" ./* -x'!'README.md -xr'!'*Image* -xr'!'*.zip
        zip -q0 "$ZIP" ./*Image*

        if [[ -n $SIGN_BUILD ]]; then
            # Remove existing (release) zip
            rm -f "${ZIP/-unsigned/}"
            # Sign zip for release
            . "$SCRIPT_DIR"/snippets/zipsigner
            zipsigner ${KEY_PAIR:+-s "$KEY_PAIR"} "$ZIP" "${ZIP/-unsigned/}"
            # Delete 'unsigned' zip
            rm "$ZIP"
        fi
    )
fi

tgNotify complete
[[ $TASK_TYPE == upload ]] && kernUpload
[[ $TASK_TYPE != build-only && -n $GENERATE_JSON ]] && genFkmJson

# Script ending
prInfo "That's it. Job well done!"
echo -ne '\a'
