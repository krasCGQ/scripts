#!/usr/bin/env bash
# KudProject kernel build tasks
# Copyright (C) 2018-2019 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

## Import common environment script
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"/../env/common

## Functions

# 'git log --pretty' alias
git_pretty() { git log --pretty=format:"%h (\"%s\")" -1; }
# Show build script duration
show_duration() { date -ud @$(($(date +%s) - START_TIME)) +'%M:%S (mm:ss)'; }
# telegram.sh message posting wrapper to avoid use of 'echo -e' and '\n'
tg_post() { "$TELEGRAM" -M -D "$(for POST in "$@"; do echo "$POST"; done)" &> /dev/null || return 0; }

# In case of signal interrupt, post interruption notification and exit script
trap '{
    [[ -n $STARTED ]] && tg_post "$MSG interrupted in $(show_duration)."
    exit 130
}' INT

# For any errors, no matter what, post error notification and exit script
tg_error() {
    # make SIGINT no-op to avoid double-posting
    trap ' ' INT
    tg_post "$MSG failed in $(show_duration)."
    [[ -n $STATUS ]] && exit "$STATUS" || exit 1
}

# Prints message to stderr and exit script, OR call tg_error function
die() {
    [[ -z $STATUS && -n $STARTED ]] && STATUS=$?
    warn "$1"
    [[ -n $STARTED ]] && tg_error || exit 1
}

# Whenever script fails, save exit status and run tg_error
trap '{
    [[ -n $STARTED ]] && STATUS=$?
    tg_error
}' ERR

## Parse parameters

parse_params() {
    [[ $# -eq 0 ]] && die "No parameter specified!"
    while [[ $# -ge 1 ]]; do
        case $1 in
            # REQUIRED
            -d | --device) shift
                # Supported devices:
                case ${1,,} in
                    grus | mido | sirius)
                        DEVICE=${1,,} ;;
                    x00t)
                        DEVICE=${1^^} ;;
                    *)
                        die "Invalid device specified!" ;;
                esac ;;

            # OPTIONAL
            -b | --build-only)
                BUILD_ONLY=true ;;

            -c | --clang)
                CLANG=true ;;

            -cv | --clang-version) shift
                # Supported latest AOSP Clang versions:
                case $1 in
                    5) CLANG_VERSION=4053586 ;;
                    6) CLANG_VERSION=4691093 ;;
                    7) CLANG_VERSION=r328903 ;;
                    8) CLANG_VERSION=r349610b ;;
                    9) CLANG_VERSION=r365631 ;;
                    *) die "Invalid version specified!" ;;
                esac ;;

            -r | --release) shift
                # Only integers are accepted
                RELEASE=$1
                [[ -n ${RELEASE//[0-9]} ]] && die "Invalid version specified!" ;;

            -s | --stock)
                STOCK=true ;;

            -u | --upload)
                # Will be ignored if BUILD_ONLY=true
                UPLOAD=true ;;

            # Unsupported parameter, skip
            *)
                warn "Unrecognized parameter specified: \"$1\"" ;;
        esac
        shift
    done
}

parse_params "$@"

# Unset these variables if they're set
for VARIABLE in CROSS_COMPILE{,_ARM32} CC; do
    [[ -n $VARIABLE ]] && unset $VARIABLE
done

## Variables

# Telegram-specific environment setup
TELEGRAM=$SCRIPTDIR/modules/telegram/telegram
tg_getid kp-on

# Paths
ROOT_DIR=$HOME/KudProject
OPT_DIR=/opt/kud

# Number of threads used
THREADS=$(nproc --all)

# GCC compiler
if [[ -z $STOCK ]] || [[ -n $CLANG && $DEVICE = mido ]]; then
    if [[ -n $CLANG ]]; then
        # Unified Binutils path
        TC_UNIFIED_BASE=binutils
        TC_UNIFIED_PATH=$TC_UNIFIED_BASE/bin
    else
        # Aarch64 toolchain
        TC_64BIT_PATH=aarch64-linux-gnu/bin
        # Aarch32 toolchain, required for compat vDSO
        TC_32BIT_PATH=arm-linux-gnueabi/bin
    fi

    # Compiler prefixes
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_ARM32=arm-linux-gnueabi-
else
    # Aarch64 toolchain
    TC_64BIT_PATH=aarch64-linux-android-4.9/bin
    CROSS_COMPILE=aarch64-linux-android-

    # Aarch32 toolchain, required for compat vDSO
    TC_32BIT_PATH=arm-linux-androideabi-4.9/bin
    CROSS_COMPILE_ARM32=arm-linux-androideabi-
fi

# Clang (if used) compiler
if [[ -n $CLANG ]]; then
    [[ -z $STOCK ]] && CLANG_PATH=clang/bin || CLANG_PATH=android-clang/clang-$CLANG_VERSION/bin
fi

# Set PATHs here to be used later while building
if [[ -n $CLANG && -z $STOCK ]]; then
    TC_UNIFIED_PATH=$OPT_DIR/$TC_UNIFIED_PATH
    TC_PATHs=$TC_UNIFIED_PATH
else
    TC_64BIT_PATH=$OPT_DIR/$TC_64BIT_PATH
    TC_32BIT_PATH=$OPT_DIR/$TC_32BIT_PATH
    TC_PATHs=$TC_64BIT_PATH:$TC_32BIT_PATH
fi
[[ -n $CLANG ]] && CLANG_PATH=$OPT_DIR/$CLANG_PATH

# Kernel build variables
AK=$ROOT_DIR/AnyKernel2/$DEVICE
ARCH=arm64
NAME=KudKernel
OUT=$ROOT_DIR/kernels/build/$DEVICE
DTS_DIR=$OUT/arch/arm64/boot/dts/qcom
[[ -n $RELEASE ]] && export KBUILD_BUILD_VERSION=$RELEASE
# Enable system-as-root flag for selected devices
[[ $DEVICE = grus ]] && SYSTEM_AS_ROOT=true

# Default message for posting to Telegram
MSG="*[BuildCI]* Kernel build job for #$DEVICE"
BRANCH=$(git rev-parse --abbrev-ref HEAD)
[[ $DEVICE != mido ]] && NAME=$BRANCH

# Default kernel build username for CI builds
[[ -z $RELEASE ]] && export KBUILD_BUILD_USER=BuildCI

## Commands

# Run this inside kernel source
[[ ! -f Makefile || ! -d kernel ]] && die "Please run this script inside kernel source folder!"

# Sanity checks
info "Running sanity checks..."
sleep 1

# Missing and device choice
[[ -z $DEVICE ]] && die "Missing device option!"
# Requested to only build; upload option is practically doing nothing
if [[ -n $UPLOAD && -n $BUILD_ONLY ]]; then
    warn "Requested to only build but upload was assigned, disabling."
    unset UPLOAD
fi
# We're not going to assume Clang version for non-AOSP one
if [[ -n $CLANG_VERSION && -z $STOCK ]]; then
    warn "Assigning Clang version is only meant for AOSP Clang, disabling."
    unset CLANG_VERSION
fi
# Missing GCC and/or Clang
for VARIABLE in ${TC_64BIT_PATH:-$TC_UNIFIED_PATH}/${CROSS_COMPILE}elfedit ${TC_32BIT_PATH:-$TC_UNIFIED_PATH}/${CROSS_COMPILE_ARM32}elfedit ${CLANG_PATH:+$CLANG_PATH/clang}; do
    find $VARIABLE &> /dev/null || die "$BLD$(basename "$VARIABLE")$RST doesn't exist in defined path."
done
# CAF's gcc-wrapper.py is shit, trust me
if [[ ! -f scripts/gcc-wrapper.py ]] && ! grep -q gcc-wrapper.py Makefile; then
    GCC_WRAPPER=false
fi
# Missing device's AnyKernel resource
[[ -z $BUILD_ONLY && ! -d $AK ]] && die "$BLD$(basename "$AK")$RST doesn't exist in defined path."

# Script beginning
info "Starting build script..."
tg_post "$MSG has been started on \`$(hostname)\`." \
        "" "Branch \`${BRANCH:-HEAD}\` at commit *$(git_pretty)*."
# Explicitly declare build script startup
STARTED=true
START_TIME=$(date +%s)
sleep 1

# Make '**' recursive
shopt -s globstar

# Clang-only setup
if [[ -n $CLANG ]]; then
    # Define additional parameters that'll be passed to make
    CLANG_EXTRAS=( "CC=clang"
                   "CLANG_TRIPLE=aarch64-linux-gnu"
                   "CLANG_TRIPLE_ARM32=arm-linux-gnueabi" )

    # Export custom compiler string for AOSP variant
    if [[ -n $STOCK ]]; then
        KBUILD_COMPILER_STRING=$($CLANG_PATH/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
        export KBUILD_COMPILER_STRING
    fi
fi

# Set up main build targets
[[ -n $SYSTEM_AS_ROOT ]] && TARGETS=( Image dtbs ) || TARGETS=( Image.gz-dtb )

# Clean build directory
info "Cleaning build directory..."
# TODO: Completely clean build?
make -s ARCH=$ARCH O="$OUT" clean
# Delete earlier dtbo.img created by this build script
rm -f "$OUT"/arch/arm64/boot/dts/qcom/dtbo.img

# Regenerate config for source changes when required
if [[ -f $OUT/.config ]]; then
    info "Regenerating config for source changes..."
    make -s ARCH=$ARCH O="$OUT" oldconfig
# However, if config file doesn't exist, generate a fresh config
else
    info "Generating a new config..."
    read -rp "  Input a defconfig name (without '_defconfig'): " DEFCONFIG
    # If defconfig name is empty, assume device name as defconfig name instead
    [[ -z $DEFCONFIG ]] && DEFCONFIG=$DEVICE
    make -j"$THREADS" -s ARCH=$ARCH O="$OUT" "${DEFCONFIG}"_defconfig
fi

# Only execute modules build if it's explicitly needed
grep -q '=m' "$OUT"/.config && HAS_MODULES=true
# Whether target needs DTBO
grep -q 'BUILD_ARM64_DT_OVERLAY=y' "$OUT"/.config && NEEDS_DTBO=true

# Let's build the kernel!
info "Building kernel..."
# Export new LD_LIBRARY_PATH before building; should be safe for all targets
export LD_LIBRARY_PATH=${TC_UNIFIED_PATH:+$OPT_DIR/$TC_UNIFIED_BASE/lib}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
PATH=$(test -n $CLANG_PATH && echo "$CLANG_PATH:")$TC_PATHs:$PATH \
make -j"$THREADS" ${GCC_WRAPPER:+-s} \
     ARCH=$ARCH O="$OUT" CROSS_COMPILE="$CROSS_COMPILE" \
     CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32" "${CLANG_EXTRAS[@]}" \
     "${TARGETS[@]}" ${HAS_MODULES:+modules}

# Build dtbo.img if needed
if [[ -n $NEEDS_DTBO ]]; then
    info "Creating dtbo.img..."
    python2 "$SCRIPTDIR"/modules/libufdt/utils/src/mkdtboimg.py \
        create "$DTS_DIR"/dtbo.img --page_size=4096 "$DTS_DIR"/*.dtbo
fi

if [[ -z $BUILD_ONLY ]]; then
    info "Cleaning and copying required file(s) to AnyKernel folder..."
    # Clean everything except zip files
    git -C "$AK" clean -qdfx -e '*.zip'
    # Kernel image task(s)
    if [[ -n $SYSTEM_AS_ROOT ]]; then
        mkdir "$AK"/files
        # Copy uncompressed kernel image and DTBs
        for FILES in "$OUT"/arch/arm64/boot/Image "$DTS_DIR"/*.dtb; do
            cp -f "$FILES" "$AK"/files
        done
    else
        # Copy compressed kernel with appended DTB image
        cp -f "$OUT"/arch/arm64/boot/Image.gz-dtb "$AK"
    fi
    # Copy dtbo.img for supported devices
    [[ -n $NEEDS_DTBO ]] && cp -f "$DTS_DIR"/dtbo.img "$AK"
    # Copy kernel modules if target device has them
    if [[ -n $HAS_MODULES ]]; then
        mkdir -p "$AK"/modules/vendor/lib/modules
        for MODULE in "$OUT"/**/*.ko; do
            cp -f "$MODULE" "$AK"/modules/vendor/lib/modules
        done
    fi

    # Export here to be picked later
    ZIP=$NAME-$DEVICE-$(date +%Y%m%d-%H%M).zip
    [[ -n $RELEASE ]] && RELEASE_ZIP=$NAME-$DEVICE-r$RELEASE-$(date +%Y%m%d).zip

    # Make flashable kernel zip
    info "Creating $ZIP..."
    (
        # Unlikely to fail; but we have to define this way to satisfy shellcheck
        cd "$AK" || die "$BLD$(basename "$AK")$RST doesn't exist in defined path."

        7za a -bso0 -mx=9 -mpass=15 -mmt="$THREADS" "$ZIP" \
            ./* -x'!'README.md -xr'!'*.zip

        if [[ -n $RELEASE ]]; then
            # Remove existing release zip if available
            [[ -f $RELEASE_ZIP ]] && rm -f "$RELEASE_ZIP"

            # Sign zip for release
            zipsigner -s "$HOME"/.android-certs/releasekey "$ZIP" "$RELEASE_ZIP"

            # Delete 'unsigned' zip
            rm -f "$ZIP"
        fi
    )
fi

# Notify successful build completion
tg_post "$MSG completed in $(show_duration)."
unset STARTED

# Upload kernel zip if requested, else the end
if [[ -n $UPLOAD ]]; then
    if [[ -z $RELEASE ]]; then
        # To Telegram
        info "Uploading $ZIP to Telegram..."
        tg_post "*[BuildCI]* Uploading test build..."
        if ! "$TELEGRAM" -f "$AK/$ZIP" -c "-1001494373196" \
            "New #$DEVICE test build with branch $BRANCH at commit $(git_pretty)."; then
            warn "Failed to upload $ZIP."
            tg_post "*[BuildCI]* Unable to upload the build."
        fi
    else
        # or to webserver for release zip
        (
            # Kernel path
            KERNEL_DIR=kernels/$DEVICE

            # Unlikely to fail; but we have to define this way to satisfy shellcheck
            cd "$AK" || die "$BLD$(basename "$AK")$RST doesn't exist in defined path."

            info "Uploading $RELEASE_ZIP..."
            if { rsync -qP --relative "$RELEASE_ZIP" krascgq@dl.kudnet.id:/var/www/dl.kudnet.id/"$KERNEL_DIR"/;
                 rsync -qP -e 'ssh -p 1983' --relative "$RELEASE_ZIP" kud@dl.wafuu.id:/var/www/dl.wafuu.id/"$KERNEL_DIR"/;
                 rsync -qP --relative "$RELEASE_ZIP" krascgq@storage.osdn.net:/storage/groups/k/ku/kudproject/"$KERNEL_DIR"/; }; then
                info "$RELEASE_ZIP uploaded successfully." \
                     "GitHub releases and AndroidFileHost uploads need manual intervention, though."
                TELEGRAM_CHAT="-1001368407111 -1001181003922" \
                tg_post "*New KudKernel build is available!*" \
                        "*Name:* \`$RELEASE_ZIP\`" \
                        "*Build Date:* \`$(sed '4q;d' "$OUT"/include/generated/compile.h | cut -d ' ' -f 6-11 | sed -e s/\"//)\`" \
                        "*Downloads:* [Webserver](https://dl.kudnet.id/$KERNEL_DIR/$RELEASE_ZIP) | [Mirror](https://dl.wafuu.id/$KERNEL_DIR/$RELEASE_ZIP) - [CDN](https://dl-cdn.wafuu.id/$KERNEL_DIR/$RELEASE_ZIP) | [OSDN](https://osdn.net/dl/kudproject/$RELEASE_ZIP)"
            else
                warn "Failed to upload $RELEASE_ZIP."
            fi
        )
    fi
fi

# Script ending
info "That's it. Job well done!"
shopt -u globstar
echo -ne '\a'
