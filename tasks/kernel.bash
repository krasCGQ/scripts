#!/usr/bin/env bash
# shellcheck source=/dev/null
# KudProject kernel build tasks
# Copyright (C) 2018-2020 Albert I (krasCGQ)
# SPDX-License-Identifier: GPL-3.0-or-later

## Import common kernel script
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"/kernel-common

## Functions

# 'git log --pretty' alias
git_pretty() { git log --pretty=format:"%h (\"%s\")" -1; }
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

# Wait every process before exit
trap 'wait' EXIT

## Parse parameters

parse_params() {
    [[ $# -eq 0 ]] && die "No parameter specified!"
    while [[ $# -ge 1 ]]; do
        case $1 in
            # REQUIRED
            -d | --device) shift
                # Supported devices:
                case ${1,,} in
                    grus | sirius)
                        DEVICE=${1,,}
                        PAGE_SIZE=4096 ;;
                    mido)
                        DEVICE=${1,,} ;;
                    scale)
                        DEVICE=${1,,}
                        IS_32BIT=true
                        NEEDS_DT_IMG=true
                        PAGE_SIZE=2048 ;;
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

            --clean)
                FULL_CLEAN=true
                # This can't co-exist
                unset DIRTY ;;

            -cv | --clang-version) shift
                # Supported Clang corresponding to function in kernel-common
                get_clang-ver "$1" ;;

            --debug)
                # Assume section mismatch(es) debugging as a target
                TARGETS=( "CONFIG_DEBUG_SECTION_MISMATCH=y" ) ;;

            --dirty)
                DIRTY=true
                # This can't co-exist
                unset FULL_CLEAN ;;

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

# Unset the following parameters just in case
unset LIB_PATHs TARGETS
parse_params "$@"

# Make '**' recursive
shopt -s globstar

## Variables

# Kernel version
KERNEL=$VERSION.$PATCHLEVEL

# Telegram-specific environment setup
TELEGRAM=$SCRIPTDIR/modules/telegram/telegram
# Default message for posting to Telegram
MSG="*[BuildCI]* Kernel build job for #$DEVICE ($KERNEL)"
tg_getid kp-on

# Paths
ROOT_DIR=$HOME/KudProject
OPT_DIR=/opt/kud
# Kernel path on server and OSDN File Storage
KERNEL_DIR=kernels/$DEVICE
# Number of threads used
THREADS=$(nproc --all)

# Clang compiler (if used)
[[ -n $CLANG && -z $STOCK ]] && CLANG_PATH=$OPT_DIR/proton-clang/bin
# GCC compiler
if [[ -z $STOCK ]]; then
    # Aarch64 toolchain
    TC_64BIT_PATH=aarch64-linux-gnu/bin
    # Aarch32 toolchain, required for compat vDSO on ARM64 devices
    TC_32BIT_PATH=arm-linux-gnueabi/bin
    # Compiler prefixes
    if [[ -z $IS_32BIT ]]; then
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
    if [[ -z $IS_32BIT ]]; then
        CROSS_COMPILE=aarch64-linux-android-
        CROSS_COMPILE_ARM32=arm-linux-androideabi-
    else
        # For arm-eabi-ld
        TC_32BIT_PATH_48=android/arm-eabi-4.8/bin
        CROSS_COMPILE=arm-linux-androideabi-
    fi
fi

# Set compiler PATHs and LD_LIBRARY_PATHs here to be used later while building
# FIXME: Find a way to reverse this; introduce a variable for now
[[ -n $CLANG && -z $STOCK ]] && CLANG_CUSTOM=true
if [[ -n $CLANG ]]; then
    LD_PATHs=${CLANG_PATH/bin/lib}
    if [[ -n $STOCK ]]; then
        # Include lib64 for AOSP Clang
        LD_PATHs+=:${CLANG_PATH/bin/lib64}
    elif [[ -d $OPT_DIR/binutils ]]; then
        # Only include Binutils if they're separate from Clang directory
        TC_UNIFIED_PATH=$OPT_DIR/binutils/bin
        TC_PATHs=$TC_UNIFIED_PATH
        LD_PATHs+=:$OPT_DIR/binutils/lib
    fi
fi
if [[ -z $CLANG_CUSTOM ]]; then
    if [[ -z $IS_32BIT ]]; then
        TC_64BIT_PATH=$OPT_DIR/$TC_64BIT_PATH
        TC_PATHs=$TC_64BIT_PATH
        LD_PATHs+=${LD_PATHs:+:}${TC_64BIT_PATH/bin/lib}
    fi
    TC_32BIT_PATH=$OPT_DIR/$TC_32BIT_PATH
    [[ -n $IS_32BIT && -n $STOCK ]] && TC_32BIT_PATH_48=$OPT_DIR/$TC_32BIT_PATH_48
    TC_PATHs+=${TC_PATHs:+:}$TC_32BIT_PATH${TC_32BIT_PATH_48:+:$TC_32BIT_PATH_48}
    LD_PATHs+=${LD_PATHs:+:}${TC_32BIT_PATH/bin/lib}${TC_32BIT_PATH_48:+:${TC_32BIT_PATH_48/bin/lib}}
fi
# Not exported; will be passed to make instead
PATH=${CLANG_PATH:+$CLANG_PATH:}${TC_PATHs:+$TC_PATHs}:$PATH
export LD_LIBRARY_PATH="$LD_PATHs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Kernel build variables
AK=$ROOT_DIR/AnyKernel/$DEVICE
BRANCH=$(git rev-parse --abbrev-ref HEAD)
# MoeSyndrome Kernel is only available for mido; use branch name for others
if [[ $DEVICE = mido ]]; then
    NAME=MoeSyndrome
    # Define which variant we're building
    [[ $(git rev-parse) =~ custom ]] && NAME+=-custom || NAME+=-vanilla
else
    NAME=$BRANCH
fi
# Set required ARCH, kernel name
if [[ -z $IS_32BIT ]]; then
    ARCH=arm64
    KERNEL_NAME=Image.gz
else
    ARCH=arm
    KERNEL_NAME=zImage
fi
OUT=/tmp/kernel-build/$DEVICE
OUT_KERNEL=$OUT/arch/$ARCH/boot
if [[ -n $RELEASE ]]; then
    # Release builds: Set build version
    export KBUILD_BUILD_VERSION=$RELEASE
else
    # CI builds: Set build username
    export KBUILD_BUILD_USER=BuildCI
fi

## Commands

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
for BIN in ${CROSS_COMPILE}elfedit ${CROSS_COMPILE_ARM32:+${CROSS_COMPILE_ARM32}elfedit} ${TC_32BIT_PATH_48:+arm-eabi-ld} ${CLANG:+clang}; do
    PATH="${CLANG_PATH:+$CLANG_PATH:}${TC_PATHs:+$TC_PATHs:}/dev/null" \
        command -v "$BIN" > /dev/null || die "$BLD$(basename "$BIN")$RST doesn't exist in defined path."
done
# Build-only isn't requested, but missing device's AnyKernel resource
[[ -z $BUILD_ONLY && ! -d $AK ]] && die "$BLD$(basename "$AK")$RST doesn't exist in defined path."
# CAF's gcc-wrapper.py is written in Python 2, but MSM kernels <= 3.10 doesn't
# call python2 directly without a patch from newer kernels; we have to utilize
# virtualenv2 neverthless.
if [[ -f scripts/gcc-wrapper.py ]] && grep -q gcc-wrapper.py Makefile; then
    . $OPT_DIR/venv2/bin/activate
fi

# Set compiler version here to avoid being included in total build time
[[ -z $CLANG_CUSTOM ]] && CUT=,2
[[ -n $CLANG ]] && COMPILER=$(clang --version | head -1 | cut -d \( -f 1$CUT | sed 's/[[:space:]]*$//') \
                || COMPILER=$(${CROSS_COMPILE}gcc --version | head -1)
LINKER=$(PATH=$PATH ${CROSS_COMPILE}ld --version | head -1)

# Script beginning
info "Starting build script..."
tg_post "$MSG has been started on \`$(hostname)\`." \
        "" "Branch \`${BRANCH:-HEAD}\` at commit *$(git_pretty)*." &
# Explicitly declare build script startup
STARTED=true
# shellcheck disable=SC2034
START_TIME=$(date +%s)
sleep 1

# Clang-only setup
if [[ -n $CLANG ]]; then
    # Define additional parameters that'll be passed to make
    CLANG_EXTRAS=( "CC=clang" )
    [[ -z $IS_32BIT ]] && CLANG_EXTRAS+=( "CLANG_TRIPLE=aarch64-linux-gnu" "CLANG_TRIPLE_ARM32=arm-linux-gnueabi" ) \
                       || CLANG_EXTRAS+=( "CLANG_TRIPLE=arm-linux-gnueabi" )
fi

# Clean build directory
if [[ -z $DIRTY && -d $OUT ]]; then
    info "Cleaning build directory..."
    if [[ -z $FULL_CLEAN ]]; then
        make -s ARCH=$ARCH O="$OUT" clean 2> /dev/null
        # Delete earlier dt{,bo}.img created by this build script
        rm -f "$OUT_KERNEL"/dts/dt{,bo}.img
    else
        # Remove out folder instead of doing mrproper/distclean
        rm -rf "$OUT"
    fi
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

# Announce build information; only pass as minimum as possible make variables
VERSION=$(PATH=$PATH make -s ARCH=$ARCH O="$OUT" CROSS_COMPILE_ARM32=$CROSS_COMPILE_ARM32 "${CLANG_EXTRAS[@]}" kernelrelease 2> /dev/null)
tg_post "*[BuildCI]* Build information:" "" \
        "*Kernel version:* \`$VERSION\`" \
        "*Compiler:* $COMPILER" \
        "*Linker:* $LINKER" &

# Only execute modules build if it's explicitly needed
grep -q '=m' "$OUT"/.config && HAS_MODULES=true
# Whether target needs DTBO
grep -q 'BUILD_ARM64_DT_OVERLAY=y' "$OUT"/.config && NEEDS_DTBO=true

# Let's build the kernel!
info "Building kernel${HAS_MODULES:+ and modules}..."
# Export timestamp earlier before build
KBUILD_BUILD_TIMESTAMP="$(date)"
export KBUILD_BUILD_TIMESTAMP
PATH=$PATH \
make -j"$THREADS" -s ARCH=$ARCH O="$OUT" CROSS_COMPILE=$CROSS_COMPILE \
     CROSS_COMPILE_ARM32=$CROSS_COMPILE_ARM32 "${CLANG_EXTRAS[@]}" \
     ${TC_32BIT_PATH_48:+LD=arm-eabi-ld} "${TARGETS[@]}" \
     ${IS_32BIT:+z}Image dtbs ${HAS_MODULES:+modules}

# Build dt.img and/or dtbo.img if needed
if [[ -n $NEEDS_DT_IMG ]]; then
    info "Creating dt.img..."
    "$SCRIPTDIR"/prebuilts/bin/dtbToolLineage -s $PAGE_SIZE \
        -o "$OUT_KERNEL"/dts/dt.img -p "$OUT"/scripts/dtc/ "$OUT_KERNEL"/dts/ > /dev/null
fi
if [[ -n $NEEDS_DTBO ]]; then
    info "Creating dtbo.img..."
    python2 "$SCRIPTDIR"/modules/libufdt/utils/src/mkdtboimg.py create \
        "$OUT_KERNEL"/dts/dtbo.img --page_size=$PAGE_SIZE \
        "$OUT_KERNEL"/dts/**/*.dtbo
fi

if [[ -z $BUILD_ONLY ]]; then
    info "Cleaning and copying required file(s) to AnyKernel folder..."
    # Clean everything except zip files
    git -C "$AK" clean -qdfx -e '*.zip'
    # ARM64: Compress resulting kernel image with fastest compression
    [[ -z $IS_32BIT ]] && gzip -f9 "$OUT_KERNEL"/Image
    if [[ -n $NEEDS_DT_IMG ]]; then
        # Copy compressed kernel image and dt.img
        cp -f "$OUT_KERNEL"/$KERNEL_NAME "$AK"
        cp -f "$OUT_KERNEL"/dts/dt.img "$AK"
    else
        # Append dtbs to compressed kernel image and copy
        cat "$OUT_KERNEL"/$KERNEL_NAME "$OUT_KERNEL"/dts/**/*.dtb > "$AK"/$KERNEL_NAME-dtb
    fi
    # Copy dtbo.img for supported devices
    [[ -n $NEEDS_DTBO ]] && cp -f "$OUT_KERNEL"/dts/dtbo.img "$AK"
    # Copy kernel modules if target device has them
    if [[ -n $HAS_MODULES ]]; then
        mkdir -p "$AK"/modules/vendor/lib/modules
        for MODULE in "$OUT"/**/*.ko; do
            cp -f "$MODULE" "$AK"/modules/vendor/lib/modules
        done
    fi

    # Export zip name here to be picked later
    ZIP=$NAME-$DEVICE-$KERNEL-$(date +%Y%m%d-%H%M).zip
    [[ -n $RELEASE ]] && RELEASE_ZIP=$NAME-$DEVICE-r$RELEASE-$(date +%Y%m%d).zip

    # Make flashable kernel zip
    info "Creating $ZIP..."
    (
        # Unlikely to fail; but we have to define this way to satisfy shellcheck
        cd "$AK" || die "$BLD$(basename "$AK")$RST doesn't exist in defined path."

        # Create with p7zip, excluding README and any other zip
        # Store kernel image uncompressed, however
        7za a -bso0 -mx=9 -mpass=15 -mmt="$THREADS" "$ZIP" ./* -x'!'README.md -xr'!'*Image* -xr'!'*.zip
        zip -q0 "$ZIP" ./*Image*

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
tg_post "$MSG completed in $(show_duration)." &
unset STARTED

# Upload kernel zip if requested, else the end
if [[ -n $UPLOAD ]]; then
    if [[ -z $RELEASE ]]; then
        # To Telegram
        info "Uploading $ZIP to Telegram..."
        tg_post "*[BuildCI]* Uploading test build..." &
        if ! "$TELEGRAM" -f "$AK/$ZIP" -c "-1001494373196" \
            "New #$DEVICE test build ($KERNEL) with branch $BRANCH at commit $(git_pretty)."; then
            warn "Failed to upload $ZIP."
            tg_post "*[BuildCI]* Unable to upload the build." &
        fi
    else
        # or to webserver for release zip
        (
            # Unlikely to fail; but we have to define this way to satisfy shellcheck
            cd "$AK" || die "$BLD$(basename "$AK")$RST doesn't exist in defined path."

            info "Uploading $RELEASE_ZIP..."
            if { rsync -qP --relative "$RELEASE_ZIP" krascgq@dl.kudnet.id:/var/www/dl.kudnet.id/"$KERNEL_DIR"/;
                 rsync -qP --relative "$RELEASE_ZIP" krascgq@storage.osdn.net:/storage/groups/k/ku/kudproject/"$KERNEL_DIR"/; }; then
                info "$RELEASE_ZIP uploaded successfully." \
                     "GitHub releases upload requires manual intervention, though."
                TELEGRAM_CHAT="-1001368407111 -1001181003922" \
                tg_post "*New MoeSyndrome Kernel build is available!*" \
                        "*Name:* \`$RELEASE_ZIP\`" \
                        "*Build Date:* \`$(sed '4q;d' "$OUT"/include/generated/compile.h | cut -d ' ' -f 6-11 | sed -e s/\"//)\`" \
                        "*Downloads:* [Webserver](https://dl.kudnet.id/$KERNEL_DIR/$RELEASE_ZIP) | [OSDN](https://osdn.net/dl/kudproject/$RELEASE_ZIP)" &
            else
                warn "Failed to upload $RELEASE_ZIP."
            fi
        )
    fi
fi

# Script ending
info "That's it. Job well done!"
echo -ne '\a'
