#!/usr/bin/env bash
# shellcheck source=/dev/null
# KudProject kernel build tasks
# Copyright (C) 2018-2019 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

## Import common environment script
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
                    scale)
                        DEVICE=${1,,}
                        unset IS_64BIT ;;
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
                    5) CLANG_VERSION=4053586 ;;  # 5.0.300080
                    6) CLANG_VERSION=4691093 ;;  # 6.0.2
                    7) CLANG_VERSION=r328903 ;;  # 7.0.2
                    8) CLANG_VERSION=r349610b ;; # 8.0.9
                    9) CLANG_VERSION=r365631c ;; # 9.0.8
                    10) CLANG_VERSION=r370808 ;; # 10.0.1
                    *) die "Invalid version specified!" ;;
                esac ;;

            --debug)
                # Assume section mismatch(es) debugging as a target
                TARGETS=( "CONFIG_DEBUG_SECTION_MISMATCH=y" ) ;;

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

# Assume target device is 64-bit
IS_64BIT=true
# Unset build targets just in case
unset TARGETS
parse_params "$@"

# Make '**' recursive
shopt -s globstar

## Variables

# Telegram-specific environment setup
TELEGRAM=$SCRIPTDIR/modules/telegram/telegram
# Default message for posting to Telegram
MSG="*[BuildCI]* Kernel build job for #$DEVICE"
tg_getid kp-on

# Paths
ROOT_DIR=$HOME/KudProject
OPT_DIR=/opt/kud
# Kernel path on server and OSDN File Storage
KERNEL_DIR=kernels/$DEVICE
# Number of threads used
THREADS=$(nproc --all)

# Clang compiler (if used)
if [[ -n $CLANG ]]; then
    [[ -z $STOCK ]] && CLANG_PATH=proton-clang/bin || CLANG_PATH=android/clang-$CLANG_VERSION/bin
fi
# GCC compiler
if [[ -z $STOCK ]]; then
    if [[ -n $CLANG ]]; then
        # Unified Binutils path
        [[ -d $OPT_DIR/binutils ]] && TC_UNIFIED_PATH=binutils/bin || TC_UNIFIED_PATH=$CLANG_PATH
    else
        # Aarch64 toolchain
        TC_64BIT_PATH=aarch64-linux-gnu/bin
        # Aarch32 toolchain, required for compat vDSO on ARM64 devices
        TC_32BIT_PATH=arm-linux-gnueabi/bin
    fi
    # Compiler prefixes
    if [[ -n $IS_64BIT ]]; then
        CROSS_COMPILE=aarch64-linux-gnu-
        CROSS_COMPILE_ARM32=arm-linux-gnueabi-
    else
        CROSS_COMPILE=arm-linux-gnueabi-
    fi
else
    # Aarch64 toolchain
    TC_64BIT_PATH=android/aarch64-linux-android-4.9/bin
    # Aarch32 toolchain, required for compat vDSO on ARM64 devices
    TC_32BIT_PATH=android/arm-linux-androideabi-4.9/bin
    # Compiler prefixes
    if [[ -n $IS_64BIT ]]; then
        CROSS_COMPILE=aarch64-linux-android-
        CROSS_COMPILE_ARM32=arm-linux-androideabi-
    else
        CROSS_COMPILE=arm-linux-androideabi-
    fi
fi

# Set compiler PATHs here to be used later while building
if [[ -n $CLANG && -z $STOCK ]]; then
    TC_UNIFIED_PATH=$OPT_DIR/$TC_UNIFIED_PATH
    TC_PATHs=$TC_UNIFIED_PATH
else
    TC_64BIT_PATH=$OPT_DIR/$TC_64BIT_PATH
    TC_32BIT_PATH=$OPT_DIR/$TC_32BIT_PATH
    TC_PATHs=${IS_64BIT:+$TC_64BIT_PATH:}$TC_32BIT_PATH
fi
[[ -n $CLANG ]] && CLANG_PATH=$OPT_DIR/$CLANG_PATH

# Kernel build variables
AK=$ROOT_DIR/AnyKernel/$DEVICE
BRANCH=$(git rev-parse --abbrev-ref HEAD)
# KudKernel is only available for mido; use current branch name for other devices
[[ $DEVICE = mido ]] && NAME=KudKernel || NAME=$BRANCH
if [[ -n $IS_64BIT ]]; then
    ARCH=arm64
    KERNEL_NAME=Image.gz-dtb
else
    ARCH=arm
    KERNEL_NAME=zImage-dtb
fi
OUT=/tmp/kernel-build/$DEVICE
DTS_DIR=$OUT/arch/$ARCH/boot/dts/qcom
if [[ -n $RELEASE ]]; then
    # Release builds: Set build version
    export KBUILD_BUILD_VERSION=$RELEASE
else
    # CI builds: Set build username
    export KBUILD_BUILD_USER=BuildCI
fi
# Enable system-as-root flag for selected devices
[[ $DEVICE = grus ]] && SYSTEM_AS_ROOT=true

## Commands

# Run this inside kernel source
[[ ! -f Makefile || ! -d kernel ]] && die "Please run this script inside kernel source folder!"

# Sanity checks
info "Running sanity checks..."
sleep 1

# Missing device choice
[[ -z $DEVICE ]] && die "Please specify target device."
# Requested to only build; upload option is practically doing nothing
if [[ -n $UPLOAD && -n $BUILD_ONLY ]]; then
    warn "Requested to only build but upload was assigned, disabling."
    unset UPLOAD
fi
# Clang-specific checks
if [[ -n $CLANG ]]; then
    # Requested to use AOSP Clang, but desired version isn't specified
    [[ -z $CLANG_VERSION && -n $STOCK ]] && die "Please specify AOSP Clang version to use."
    # We're not going to assume Clang version for non-AOSP one
    if [[ -n $CLANG_VERSION && -z $STOCK ]]; then
        warn "Assigning Clang version is only meant for AOSP Clang, disabling."
        unset CLANG_VERSION
    fi
fi
# Missing GCC and/or Clang
for VARIABLE in ${IS_64BIT:+${TC_64BIT_PATH:-$TC_UNIFIED_PATH}/${CROSS_COMPILE}elfedit} ${TC_32BIT_PATH:-$TC_UNIFIED_PATH}/${CROSS_COMPILE_ARM32:-$CROSS_COMPILE}elfedit ${CLANG_PATH:+$CLANG_PATH/clang}; do
    find $VARIABLE &> /dev/null || die "$BLD$(basename "$VARIABLE")$RST doesn't exist in defined path."
done
# Build-only isn't requested, but missing device's AnyKernel resource
[[ -z $BUILD_ONLY && ! -d $AK ]] && die "$BLD$(basename "$AK")$RST doesn't exist in defined path."
# CAF's gcc-wrapper.py is written in Python 2, but MSM kernels <= 3.10 doesn't
# call python2 directly without a patch from newer kernels; we have to utilize
# virtualenv2 neverthless.
if [[ -f scripts/gcc-wrapper.py ]] && grep -q gcc-wrapper.py Makefile; then
    . $OPT_DIR/venv2/bin/activate
fi

# Script beginning
info "Starting build script..."
tg_post "$MSG has been started on \`$(hostname)\`." \
        "" "Branch \`${BRANCH:-HEAD}\` at commit *$(git_pretty)*."
# Explicitly declare build script startup
STARTED=true
START_TIME=$(date +%s)
sleep 1

# Clang-only setup
if [[ -n $CLANG ]]; then
    # Define additional parameters that'll be passed to make
    CLANG_EXTRAS=( "CC=clang" )
    [[ -n $IS_64BIT ]] && CLANG_EXTRAS+=( "CLANG_TRIPLE=aarch64-linux-gnu" "CLANG_TRIPLE_ARM32=arm-linux-gnueabi" ) || CLANG_EXTRAS+=( "CLANG_TRIPLE=arm-linux-gnueabi" )
    # Export custom compiler string for AOSP variant
    if [[ -n $STOCK ]]; then
        KBUILD_COMPILER_STRING=$($CLANG_PATH/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
        export KBUILD_COMPILER_STRING
    fi
fi
# Set up main build targets
[[ -n $SYSTEM_AS_ROOT ]] && TARGETS+=( Image dtbs ) || TARGETS+=( "$KERNEL_NAME" )

# Clean build directory
if [[ -d $OUT/$DEVICE ]]; then
    info "Cleaning build directory..."
    # TODO: Completely clean build?
    make -s ARCH=$ARCH O="$OUT" clean 2> /dev/null
    # Delete earlier dtbo.img created by this build script
    rm -f "$DTS_DIR"/dtbo.img
fi

# Linux kernel < 3.15 doesn't automatically create out folder without an upstream
# patch. We have to do this manually otherwise such kernel will cause an error.
[[ ! -d $OUT/$DEVICE ]] && mkdir -p "$OUT"/"$DEVICE"

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
export LD_LIBRARY_PATH=${TC_UNIFIED_PATH:+$(dirname $TC_UNIFIED_PATH)/lib}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
PATH=${CLANG_PATH:+$CLANG_PATH:}$TC_PATHs:$PATH \
make -j"$THREADS" -s ARCH=$ARCH O="$OUT" CROSS_COMPILE="$CROSS_COMPILE" \
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
        for FILES in "$OUT"/arch/$ARCH/boot/Image "$DTS_DIR"/*.dtb; do
            cp -f "$FILES" "$AK"/files
        done
    else
        # Copy compressed kernel with appended DTB image
        cp -f "$OUT"/arch/$ARCH/boot/$KERNEL_NAME "$AK"
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

    # Export zip name here to be picked later
    ZIP=$NAME-$DEVICE-$(date +%Y%m%d-%H%M).zip
    [[ -n $RELEASE ]] && RELEASE_ZIP=$NAME-$DEVICE-r$RELEASE-$(date +%Y%m%d).zip

    # Make flashable kernel zip
    info "Creating $ZIP..."
    (
        # Unlikely to fail; but we have to define this way to satisfy shellcheck
        cd "$AK" || die "$BLD$(basename "$AK")$RST doesn't exist in defined path."

        # Create with p7zip, excluding README and any other zip
        7za a -bso0 -mx=9 -mpass=15 -mmt="$THREADS" "$ZIP" ./* -x'!'README.md -xr'!'*.zip

        if [[ -n $RELEASE ]]; then
            # Remove existing release zip
            rm -f "$RELEASE_ZIP"
            # Sign zip for release
            zipsigner -s "$HOME"/.android-certs/releasekey "$ZIP" "$RELEASE_ZIP"
            # Delete 'unsigned' zip
            rm -f "$ZIP"
        fi
    )
fi

# Notify successful build
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
echo -ne '\a'
