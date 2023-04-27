#!/bin/bash
#
# This file is part of MagiskOnWSALocal.
#
# MagiskOnWSALocal is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# MagiskOnWSALocal is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with MagiskOnWSALocal.  If not, see <https://www.gnu.org/licenses/>.
#
# Copyright (C) 2023 LSPosed Contributors
#

if [ ! "$BASH_VERSION" ]; then
    echo "Please do not use sh to run this script, just execute it directly" 1>&2
    exit 1
fi
HOST_ARCH=$(uname -m)
if [ "$HOST_ARCH" != "x86_64" ] && [ "$HOST_ARCH" != "aarch64" ]; then
    echo "Unsupported architectures: $HOST_ARCH"
    exit 1
fi
cd "$(dirname "$0")" || exit 1
# export TMPDIR=$(dirname "$PWD")/WORK_DIR_
if [ "$TMPDIR" ] && [ ! -d "$TMPDIR" ]; then
    mkdir -p "$TMPDIR"
fi
WORK_DIR=$(mktemp -d -t wsa-build-XXXXXXXXXX_) || exit 1
ROOT_MNT="$WORK_DIR/system_root"
SYSTEM_MNT="$ROOT_MNT/system"
VENDOR_MNT="$ROOT_MNT/vendor"
PRODUCT_MNT="$ROOT_MNT/product"
SYSTEM_EXT_MNT="$ROOT_MNT/system_ext"
DOWNLOAD_DIR=../download
DOWNLOAD_CONF_NAME=download.list
umount_clean() {
    if [ -d "$ROOT_MNT" ]; then
        echo "Cleanup Mount Directory"
        if [ -d "$VENDOR_MNT" ]; then
            sudo umount -v "$VENDOR_MNT"
        fi
        if [ -d "$PRODUCT_MNT" ]; then
            sudo umount -v "$PRODUCT_MNT"
        fi
        if [ -d "$SYSTEM_EXT_MNT" ]; then
            sudo umount -v "$SYSTEM_EXT_MNT"
        fi
        sudo umount -v "$ROOT_MNT"

        sudo rm -rf "${WORK_DIR:?}"
    else
        rm -rf "${WORK_DIR:?}"
    fi
    if [ "$TMPDIR" ] && [ -d "$TMPDIR" ]; then
        echo "Cleanup Temp Directory"
        rm -rf "${TMPDIR:?}"
        unset TMPDIR
    fi
    rm -f "${DOWNLOAD_DIR:?}/$DOWNLOAD_CONF_NAME"
}
trap umount_clean EXIT
OUTPUT_DIR=../output
WSA_WORK_ENV="${WORK_DIR:?}/ENV"
if [ -f "$WSA_WORK_ENV" ]; then rm -f "${WSA_WORK_ENV:?}"; fi
touch "$WSA_WORK_ENV"
export WSA_WORK_ENV
clean_download() {
    if [ -d "$DOWNLOAD_DIR" ]; then
        echo "Cleanup Download Directory"
        if [ "$CLEAN_DOWNLOAD_WSA" ]; then
            rm -f "${WSA_ZIP_PATH:?}"
        fi
        if [ "$CLEAN_DOWNLOAD_MAGISK" ]; then
            rm -f "${MAGISK_PATH:?}"
        fi
        if [ "$CLEAN_DOWNLOAD_GAPPS" ]; then
            rm -f "${GAPPS_PATH:?}"
        fi
        if [ "$CLEAN_DOWNLOAD_KERNELSU" ]; then
            rm -f "${KERNELSU_PATH:?}"
            rm -f "${KERNELSU_INFO:?}"
        fi
    fi
}
abort() {
    echo "Build: an error has occurred, exit"
    if [ -d "$WORK_DIR" ]; then
        echo -e "\nCleanup Work Directory"
        umount_clean
    fi
    clean_download
    exit 1
}
trap abort INT TERM

Gen_Rand_Str() {
    head /dev/urandom | tr -dc '[:lower:]' | head -c"$1"
}

default() {
    ARCH=x64
    RELEASE_TYPE=retail
    MAGISK_VER=stable
    GAPPS_BRAND=MindTheGapps
    GAPPS_VARIANT=pico
    ROOT_SOL=magisk
}

exit_with_message() {
    echo "ERROR: $1"
    usage
    exit 1
}

resize_img() {
    e2fsck -pf "$1" || return 1
    if [ "$2" ]; then
        resize2fs "$1" "$2" || return 1
    else
        resize2fs -M "$1" || return 1
    fi
    return 0
}

vhdx_to_img() {
    qemu-img convert -q -f vhdx -O raw "$1" "$2" || return 1
    resize_img "$2" "$(($(du --apparent-size -sB512 "$2" | cut -f1) * 2))"s || return 1
    e2fsck -fp -E unshare_blocks "$2" || return 1
    resize_img "$2" || return 1
    rm -f "$1" || return 1
    return 0
}

# workaround for Debian
# In Debian /usr/sbin is not in PATH and some utilities are not in /bin
[ -d /usr/sbin ] && export PATH="/usr/sbin:$PATH"
# In Debian /etc/mtab is not exist
[ -f /etc/mtab ] || ln -s /proc/self/mounts /etc/mtab

ARCH_MAP=(
    "x64"
    "arm64"
)

RELEASE_TYPE_MAP=(
    "retail"
    "RP"
    "WIS"
    "WIF"
)

MAGISK_VER_MAP=(
    "stable"
    "beta"
    "canary"
    "debug"
    "release"
    "delta"
)

GAPPS_BRAND_MAP=(
    "OpenGApps"
    "MindTheGapps"
    "none"
)

GAPPS_VARIANT_MAP=(
    "super"
    "stock"
    "full"
    "mini"
    "micro"
    "nano"
    "pico"
    "tvstock"
    "tvmini"
)

ROOT_SOL_MAP=(
    "magisk"
    "kernelsu"
    "none"
)

COMPRESS_FORMAT_MAP=(
    "7z"
    "xz"
    "zip"
)

ARR_TO_STR() {
    local arr=("$@")
    local joined
    printf -v joined "%s, " "${arr[@]}"
    echo "${joined%, }"
}
GAPPS_PROPS_MSG1="\033[0;31mWARNING: Services such as the Play Store may stop working properly."
GAPPS_PROPS_MSG2="We are not responsible for any problems caused by this!\033[0m"
GAPPS_PROPS_MSG3="Info: https://support.google.com/android/answer/10248227"
usage() {
    default
    echo -e "
Usage:
    --arch              Architecture of WSA.

                        Possible values: $(ARR_TO_STR "${ARCH_MAP[@]}")
                        Default: $ARCH

    --release-type      Release type of WSA.
                        RP means Release Preview, WIS means Insider Slow, WIF means Insider Fast.

                        Possible values: $(ARR_TO_STR "${RELEASE_TYPE_MAP[@]}")
                        Default: $RELEASE_TYPE

    --magisk-ver        Magisk version.

                        Possible values: $(ARR_TO_STR "${MAGISK_VER_MAP[@]}")
                        Default: $MAGISK_VER

    --gapps-brand       GApps brand.
                        \"none\" for no integration of GApps

                        Possible values: $(ARR_TO_STR "${GAPPS_BRAND_MAP[@]}")
                        Default: $GAPPS_BRAND

    --gapps-variant     GApps variant.

                        Possible values: $(ARR_TO_STR "${GAPPS_VARIANT_MAP[@]}")
                        Default: $GAPPS_VARIANT

    --root-sol          Root solution.
                        \"none\" means no root.

                        Possible values: $(ARR_TO_STR "${ROOT_SOL_MAP[@]}")
                        Default: $ROOT_SOL

    --compress-format
                        Compress format of output file.
                        If this option is not specified and --compress is not specified, the generated file will not be compressed

                        Possible values: $(ARR_TO_STR "${COMPRESS_FORMAT_MAP[@]}")

Additional Options:
    --remove-amazon     Remove Amazon Appstore from the system
    --compress          Compress the WSA, The default format is 7z, you can use the format specified by --compress-format
    --offline           Build WSA offline
    --magisk-custom     Install custom Magisk
    --skip-download-wsa Skip download WSA
    --debug             Debug build mode
    --help              Show this help message and exit
    --nofix-props       No fix \"build.prop\"
                        $GAPPS_PROPS_MSG1
                        $GAPPS_PROPS_MSG2
                        $GAPPS_PROPS_MSG3

Example:
    ./build.sh --release-type RP --magisk-ver beta --gapps-variant pico --remove-amazon
    ./build.sh --arch arm64 --release-type WIF --gapps-brand OpenGApps --nofix-props
    ./build.sh --release-type WIS --gapps-brand none
    ./build.sh --offline --gapps-variant pico --magisk-custom
    "
}

ARGUMENT_LIST=(
    "arch:"
    "release-type:"
    "magisk-ver:"
    "gapps-brand:"
    "gapps-variant:"
    "nofix-props"
    "root-sol:"
    "compress-format:"
    "remove-amazon"
    "compress"
    "offline"
    "magisk-custom"
    "debug"
    "help"
    "skip-download-wsa"
)

default

opts=$(
    getopt \
        --longoptions "$(printf "%s," "${ARGUMENT_LIST[@]}")" \
        --name "$(basename "$0")" \
        --options "" \
        -- "$@"
) || exit_with_message "Failed to parse options, please check your input"

eval set --"$opts"
while [[ $# -gt 0 ]]; do
   case "$1" in
        --arch              ) ARCH="$2"; shift 2 ;;
        --release-type      ) RELEASE_TYPE="$2"; shift 2 ;;
        --gapps-brand       ) GAPPS_BRAND="$2"; shift 2 ;;
        --gapps-variant     ) GAPPS_VARIANT="$2"; shift 2 ;;
        --nofix-props       ) NOFIX_PROPS="yes"; shift ;;
        --root-sol          ) ROOT_SOL="$2"; shift 2 ;;
        --compress-format   ) COMPRESS_FORMAT="$2"; shift 2 ;;
        --remove-amazon     ) REMOVE_AMAZON="yes"; shift ;;
        --compress          ) COMPRESS_OUTPUT="yes"; shift ;;
        --offline           ) OFFLINE="on"; shift ;;
        --magisk-custom     ) CUSTOM_MAGISK="debug"; shift ;;
        --magisk-ver        ) MAGISK_VER="$2"; shift 2 ;;
        --debug             ) DEBUG="on"; shift ;;
        --skip-download-wsa ) DOWN_WSA="no"; shift ;;
        --help              ) usage; exit 0 ;;
        --                  ) shift; break;;
   esac
done

if [ "$CUSTOM_MAGISK" ]; then
    if [ -z "$MAGISK_VER" ]; then
        MAGISK_VER=$CUSTOM_MAGISK
    fi
fi

check_list() {
    local input=$1
    if [ -n "$input" ]; then
        local name=$2
        shift
        local arr=("$@")
        local list_count=${#arr[@]}
        for i in "${arr[@]}"; do
            if [ "$input" == "$i" ]; then
                echo "INFO: $name: $input"
                break
            fi
            ((list_count--))
            if (("$list_count" <= 0)); then
                exit_with_message "Invalid $name: $input"
            fi
        done
    fi
}

check_list "$ARCH" "Architecture" "${ARCH_MAP[@]}"
check_list "$RELEASE_TYPE" "Release Type" "${RELEASE_TYPE_MAP[@]}"
check_list "$MAGISK_VER" "Magisk Version" "${MAGISK_VER_MAP[@]}"
check_list "$GAPPS_BRAND" "GApps Brand" "${GAPPS_BRAND_MAP[@]}"
check_list "$GAPPS_VARIANT" "GApps Variant" "${GAPPS_VARIANT_MAP[@]}"
check_list "$ROOT_SOL" "Root Solution" "${ROOT_SOL_MAP[@]}"
check_list "$COMPRESS_FORMAT" "Compress Format" "${COMPRESS_FORMAT_MAP[@]}"

if [ "$DEBUG" ]; then
    set -x
fi

require_su() {
    if test "$(id -u)" != "0"; then
        if [ "$(sudo id -u)" != "0" ]; then
            echo "ROOT/SUDO is required to run this script"
            abort
        fi
    fi
}

declare -A RELEASE_NAME_MAP=(["retail"]="Retail" ["RP"]="Release Preview" ["WIS"]="Insider Slow" ["WIF"]="Insider Fast")
declare -A ANDROID_API_MAP=(["30"]="11.0" ["32"]="12.1" ["33"]="13.0")
RELEASE_NAME=${RELEASE_NAME_MAP[$RELEASE_TYPE]} || abort

echo -e "Build: RELEASE_TYPE=$RELEASE_NAME"

WSA_ZIP_PATH=$DOWNLOAD_DIR/wsa-$RELEASE_TYPE.zip
vclibs_PATH="$DOWNLOAD_DIR/Microsoft.VCLibs.140.00_$ARCH.appx"
UWPVCLibs_PATH="$DOWNLOAD_DIR/Microsoft.VCLibs.140.00.UWPDesktop_$ARCH.appx"
xaml_PATH="$DOWNLOAD_DIR/Microsoft.UI.Xaml.2.8_$ARCH.appx"
MAGISK_ZIP=magisk-$MAGISK_VER.zip
MAGISK_PATH=$DOWNLOAD_DIR/$MAGISK_ZIP
if [ "$CUSTOM_MAGISK" ]; then
    if [ ! -f "$MAGISK_PATH" ]; then
        echo "Custom Magisk $MAGISK_ZIP not found"
        MAGISK_ZIP=app-$MAGISK_VER.apk
        echo "Fallback to $MAGISK_ZIP"
        MAGISK_PATH=$DOWNLOAD_DIR/$MAGISK_ZIP
        if [ ! -f "$MAGISK_PATH" ]; then
            echo -e "Custom Magisk $MAGISK_ZIP not found\nPlease put custom Magisk in $DOWNLOAD_DIR"
            abort
        fi
    fi
fi
ANDROID_API=33
update_gapps_zip_name() {
    if [ "$GAPPS_BRAND" = "OpenGApps" ]; then
        ANDROID_API=30
        GAPPS_ZIP_NAME=$GAPPS_BRAND-$ARCH-${ANDROID_API_MAP[$ANDROID_API]}-$GAPPS_VARIANT.zip
    else
        GAPPS_ZIP_NAME=$GAPPS_BRAND-$ARCH-${ANDROID_API_MAP[$ANDROID_API]}.zip
    fi
    GAPPS_PATH=$DOWNLOAD_DIR/$GAPPS_ZIP_NAME
}
DOWN_WSA_MAIN_VERSION=0
update_ksu_zip_name() {
    if [ "$DOWN_WSA_MAIN_VERSION" -lt "2303" ]; then
        KERNEL_VER="5.10.117.2"
    else
        KERNEL_VER="5.15.78.1"
    fi
    KERNELSU_ZIP_NAME=kernelsu-$ARCH-$KERNEL_VER.zip
    KERNELSU_PATH=$DOWNLOAD_DIR/$KERNELSU_ZIP_NAME
    KERNELSU_INFO="$KERNELSU_PATH.info"
}
update_gapps_zip_name
update_ksu_zip_name
if [ -z ${OFFLINE+x} ]; then
    require_su
    if [ "$DOWN_WSA" != "no" ]; then
        echo "Generate Download Links"
        python3 generateWSALinks.py "$ARCH" "$RELEASE_TYPE" "$DOWNLOAD_DIR" "$DOWNLOAD_CONF_NAME" || abort
        # shellcheck disable=SC1090
        source "$WSA_WORK_ENV" || abort
    else
        DOWN_WSA_MAIN_VERSION=$(python3 getWSAMainVersion.py "$ARCH" "$WSA_ZIP_PATH")
    fi
    if [[ "$DOWN_WSA_MAIN_VERSION" -lt 2211 ]]; then
        ANDROID_API=32
        update_gapps_zip_name
    fi
    if [[ "$DOWN_WSA_MAIN_VERSION" -ge 2303 ]]; then
        update_ksu_zip_name
    fi
    if [ "$ROOT_SOL" = "magisk" ] || [ "$GAPPS_BRAND" != "none" ]; then
        if [ -z ${CUSTOM_MAGISK+x} ]; then
            python3 generateMagiskLink.py "$MAGISK_VER" "$DOWNLOAD_DIR" "$DOWNLOAD_CONF_NAME" || abort
        fi
    fi
    if [ "$ROOT_SOL" = "kernelsu" ]; then
        python3 generateKernelSULink.py "$ARCH" "$DOWNLOAD_DIR" "$DOWNLOAD_CONF_NAME" "$KERNEL_VER" "$KERNELSU_ZIP_NAME" || abort
        # shellcheck disable=SC1090
        source "$WSA_WORK_ENV" || abort
        # shellcheck disable=SC2153
        echo "KERNELSU_VER=$KERNELSU_VER" >"$KERNELSU_INFO"
    fi
    if [ "$GAPPS_BRAND" != "none" ]; then
        python3 generateGappsLink.py "$ARCH" "$GAPPS_BRAND" "$GAPPS_VARIANT" "$DOWNLOAD_DIR" "$DOWNLOAD_CONF_NAME" "$ANDROID_API" "$GAPPS_ZIP_NAME" || abort
    fi

    echo "Download Artifacts"
    if ! aria2c --no-conf --log-level=info --log="$DOWNLOAD_DIR/aria2_download.log" -x16 -s16 -j5 -c -R -m0 --async-dns=false --check-integrity=true --continue=true --allow-overwrite=true --conditional-get=true -d"$DOWNLOAD_DIR" -i"$DOWNLOAD_DIR/$DOWNLOAD_CONF_NAME"; then
        echo "We have encountered an error while downloading files."
        exit 1
    fi
else # Offline mode
    DOWN_WSA_MAIN_VERSION=$(python3 getWSAMainVersion.py "$ARCH" "$WSA_ZIP_PATH")
    if [[ "$DOWN_WSA_MAIN_VERSION" -lt 2211 ]]; then
        ANDROID_API=32
        update_gapps_zip_name
    fi
    if [[ "$DOWN_WSA_MAIN_VERSION" -ge 2303 ]]; then
        update_ksu_zip_name
    fi
    declare -A FILES_CHECK_LIST=([WSA_ZIP_PATH]="$WSA_ZIP_PATH" [xaml_PATH]="$xaml_PATH" [vclibs_PATH]="$vclibs_PATH" [UWPVCLibs_PATH]="$UWPVCLibs_PATH")
    if [ "$GAPPS_BRAND" != "none" ] || [ "$ROOT_SOL" = "magisk" ]; then
        FILES_CHECK_LIST+=(["MAGISK_PATH"]="$MAGISK_PATH")
    fi
    if [ "$ROOT_SOL" = "kernelsu" ]; then
        FILES_CHECK_LIST+=(["KERNELSU_PATH"]="$KERNELSU_PATH")
    fi
    if [ "$GAPPS_BRAND" != 'none' ]; then
        FILES_CHECK_LIST+=(["GAPPS_PATH"]="$GAPPS_PATH")
    fi
    for i in "${FILES_CHECK_LIST[@]}"; do
        if [ ! -f "$i" ]; then
            echo "Offline mode: missing [$i]."
            OFFLINE_ERR="1"
        fi
    done
    if [ "$OFFLINE_ERR" ]; then
        echo "Offline mode: Some files are missing, please disable offline mode."
        exit 1
    fi
    require_su
fi

echo "Extract WSA"
if [ -f "$WSA_ZIP_PATH" ]; then
    if ! python3 extractWSA.py "$ARCH" "$WSA_ZIP_PATH" "$WORK_DIR" "$WSA_WORK_ENV"; then
        echo "Unzip WSA failed, is the download incomplete?"
        CLEAN_DOWNLOAD_WSA=1
        abort
    fi
    echo -e "Extract done\n"
    # shellcheck disable=SC1090
    source "$WSA_WORK_ENV" || abort
else
    echo "The WSA zip package does not exist, is the download incomplete?"
    exit 1
fi

if [ "$GAPPS_BRAND" != "none" ] || [ "$ROOT_SOL" = "magisk" ]; then
    echo "Extract Magisk"
    if [ -f "$MAGISK_PATH" ]; then
        MAGISK_VERSION_NAME=""
        MAGISK_VERSION_CODE=0
        if ! python3 extractMagisk.py "$ARCH" "$MAGISK_PATH" "$WORK_DIR"; then
            echo "Unzip Magisk failed, is the download incomplete?"
            CLEAN_DOWNLOAD_MAGISK=1
            abort
        fi
        # shellcheck disable=SC1090
        source "$WSA_WORK_ENV" || abort
        if [ "$MAGISK_VERSION_CODE" -lt 25211 ] && [ "$MAGISK_VER" != "delta" ] && [ -z ${CUSTOM_MAGISK+x} ]; then
            echo "Please install Magisk v25211+"
            abort
        fi
        sudo chmod +x "../linker/$HOST_ARCH/linker64" || abort
        sudo patchelf --set-interpreter "../linker/$HOST_ARCH/linker64" "$WORK_DIR/magisk/magiskpolicy" || abort
        chmod +x "$WORK_DIR/magisk/magiskpolicy" || abort
    elif [ -z "${CUSTOM_MAGISK+x}" ]; then
        echo "The Magisk zip package does not exist, is the download incomplete?"
        exit 1
    else
        echo "The Magisk zip package does not exist, rename it to magisk-debug.zip and put it in the download folder."
        exit 1
    fi
    echo -e "done\n"
fi

if [ "$ROOT_SOL" = "kernelsu" ]; then
    echo "Extract KernelSU"
    # shellcheck disable=SC1090
    source "${KERNELSU_INFO:?}" || abort
    if ! unzip "$KERNELSU_PATH" -d "$WORK_DIR/kernelsu"; then
        echo "Unzip KernelSU failed, package is corrupted?"
        CLEAN_DOWNLOAD_KERNELSU=1
        abort
    fi
    if [ "$ARCH" = "x64" ]; then
        mv "$WORK_DIR/kernelsu/bzImage" "$WORK_DIR/kernelsu/kernel"
    elif [ "$ARCH" = "arm64" ]; then
        mv "$WORK_DIR/kernelsu/Image" "$WORK_DIR/kernelsu/kernel"
    fi
    echo -e "done\n"
fi

if [ "$GAPPS_BRAND" != 'none' ]; then
    echo "Extract $GAPPS_BRAND"
    mkdir -p "$WORK_DIR/gapps" || abort
    if [ -f "$GAPPS_PATH" ]; then
        if [ "$GAPPS_BRAND" = "OpenGApps" ]; then
            if ! unzip -p "$GAPPS_PATH" {Core,GApps}/'*.lz' | tar --lzip -C "$WORK_DIR/gapps" -xf - -i --strip-components=2 --exclude='setupwizardtablet-x86_64' --exclude='packageinstallergoogle-all' --exclude='speech-common' --exclude='markup-lib-arm' --exclude='markup-lib-arm64' --exclude='markup-all' --exclude='setupwizarddefault-x86_64' --exclude='pixellauncher-all' --exclude='pixellauncher-common'; then
                echo "Unzip OpenGApps failed, is the download incomplete?"
                CLEAN_DOWNLOAD_GAPPS=1
                abort
            fi
        else
            if ! unzip "$GAPPS_PATH" "system/*" -x "system/addon.d/*" "system/system_ext/priv-app/SetupWizard/*" -d "$WORK_DIR/gapps"; then
                echo "Unzip MindTheGapps failed, package is corrupted?"
                CLEAN_DOWNLOAD_GAPPS=1
                abort
            fi
            mv "$WORK_DIR/gapps/system/"* "$WORK_DIR/gapps" || abort
            rm -rf "${WORK_DIR:?}/gapps/system" || abort
        fi
        cp -r "../$ARCH/gapps/"* "$WORK_DIR/gapps" || abort
    else
        echo "The $GAPPS_BRAND zip package does not exist."
        abort
    fi
    echo -e "Extract done\n"
fi

echo "Calculate the required space"
EXTRA_SIZE=10240

SYSTEM_EXT_NEED_SIZE=$EXTRA_SIZE
if [ -d "$WORK_DIR/gapps/system_ext" ]; then
    SYSTEM_EXT_NEED_SIZE=$((SYSTEM_EXT_NEED_SIZE + $(du --apparent-size -sB512 "$WORK_DIR/gapps/system_ext" | cut -f1)))
fi

PRODUCT_NEED_SIZE=$EXTRA_SIZE
if [ -d "$WORK_DIR/gapps/product" ]; then
    PRODUCT_NEED_SIZE=$((PRODUCT_NEED_SIZE + $(du --apparent-size -sB512 "$WORK_DIR/gapps/product" | cut -f1)))
fi

SYSTEM_NEED_SIZE=$EXTRA_SIZE
if [ -d "$WORK_DIR/gapps" ]; then
    SYSTEM_NEED_SIZE=$((SYSTEM_NEED_SIZE + $(du --apparent-size -sB512 "$WORK_DIR/gapps" | cut -f1) - PRODUCT_NEED_SIZE - SYSTEM_EXT_NEED_SIZE))
fi
if [ "$ROOT_SOL" = "magisk" ]; then
    if [ -d "$WORK_DIR/magisk" ]; then
        MAGISK_SIZE=$(du --apparent-size -sB512 "$WORK_DIR/magisk/magisk" | cut -f1)
        SYSTEM_NEED_SIZE=$((SYSTEM_NEED_SIZE + MAGISK_SIZE))
    fi
    if [ -f "$MAGISK_PATH" ]; then
        MAGISK_APK_SIZE=$(du --apparent-size -sB512 "$MAGISK_PATH" | cut -f1)
        SYSTEM_NEED_SIZE=$((SYSTEM_NEED_SIZE + MAGISK_APK_SIZE))
    fi
fi
if [ -d "../$ARCH/system" ]; then
    SYSTEM_NEED_SIZE=$((SYSTEM_NEED_SIZE + $(du --apparent-size -sB512 "../$ARCH/system" | cut -f1)))
fi

VENDOR_NEED_SIZE=$EXTRA_SIZE
echo -e "done\n"

echo "Expand images"
if [[ "$DOWN_WSA_MAIN_VERSION" -ge 2302 ]]; then
    echo "Convert vhdx to img and remove read-only flag"
    vhdx_to_img "$WORK_DIR/wsa/$ARCH/system_ext.vhdx" "$WORK_DIR/wsa/$ARCH/system_ext.img" || abort
    vhdx_to_img "$WORK_DIR/wsa/$ARCH/product.vhdx" "$WORK_DIR/wsa/$ARCH/product.img" || abort
    vhdx_to_img "$WORK_DIR/wsa/$ARCH/system.vhdx" "$WORK_DIR/wsa/$ARCH/system.img" || abort
    vhdx_to_img "$WORK_DIR/wsa/$ARCH/vendor.vhdx" "$WORK_DIR/wsa/$ARCH/vendor.img" || abort
    echo -e "Convert vhdx to img and remove read-only flag done\n"
fi

SYSTEM_EXT_IMG_SIZE=$(du --apparent-size -sB512 "$WORK_DIR/wsa/$ARCH/system_ext.img" | cut -f1)
PRODUCT_IMG_SIZE=$(du --apparent-size -sB512 "$WORK_DIR/wsa/$ARCH/product.img" | cut -f1)
SYSTEM_IMG_SIZE=$(du --apparent-size -sB512 "$WORK_DIR/wsa/$ARCH/system.img" | cut -f1)
VENDOR_IMG_SIZE=$(du --apparent-size -sB512 "$WORK_DIR/wsa/$ARCH/vendor.img" | cut -f1)
SYSTEM_EXT_TARGET_SIZE=$((SYSTEM_EXT_NEED_SIZE * 2 + SYSTEM_EXT_IMG_SIZE))
PRODUCT_TAGET_SIZE=$((PRODUCT_NEED_SIZE * 2 + PRODUCT_IMG_SIZE))
SYSTEM_TAGET_SIZE=$((SYSTEM_IMG_SIZE * 2))
VENDOR_TAGET_SIZE=$((VENDOR_NEED_SIZE * 2 + VENDOR_IMG_SIZE))

resize_img "$WORK_DIR/wsa/$ARCH/system_ext.img" "$SYSTEM_EXT_TARGET_SIZE"s || abort
resize_img "$WORK_DIR/wsa/$ARCH/product.img" "$PRODUCT_TAGET_SIZE"s || abort
resize_img "$WORK_DIR/wsa/$ARCH/system.img" "$SYSTEM_TAGET_SIZE"s || abort
resize_img "$WORK_DIR/wsa/$ARCH/vendor.img" "$VENDOR_TAGET_SIZE"s || abort

echo -e "Expand images done\n"

echo "Mount images"
sudo mkdir "$ROOT_MNT" || abort
sudo mount -vo loop "$WORK_DIR/wsa/$ARCH/system.img" "$ROOT_MNT" || abort
sudo mount -vo loop "$WORK_DIR/wsa/$ARCH/vendor.img" "$VENDOR_MNT" || abort
sudo mount -vo loop "$WORK_DIR/wsa/$ARCH/product.img" "$PRODUCT_MNT" || abort
sudo mount -vo loop "$WORK_DIR/wsa/$ARCH/system_ext.img" "$SYSTEM_EXT_MNT" || abort
echo -e "done\n"

if [ "$REMOVE_AMAZON" ]; then
    echo "Remove Amazon Appstore"
    find "${PRODUCT_MNT:?}"/{etc/permissions,etc/sysconfig,framework,priv-app} 2>/dev/null | grep -e amazon -e venezia | sudo xargs rm -rf
    find "${SYSTEM_EXT_MNT:?}"/{etc/*permissions,framework,priv-app} 2>/dev/null | grep -e amazon -e venezia | sudo xargs rm -rf
    echo -e "done\n"
fi

echo "Add device administration features"
sudo sed -i -e '/cts/a \ \ \ \ <feature name="android.software.device_admin" />' -e '/print/i \ \ \ \ <feature name="android.software.managed_users" />' "$VENDOR_MNT/etc/permissions/windows.permissions.xml"
sudo setfattr -n security.selinux -v "u:object_r:vendor_configs_file:s0" "$VENDOR_MNT/etc/permissions/windows.permissions.xml" || abort
echo -e "done\n"

if [ "$ROOT_SOL" = 'magisk' ]; then
    echo "Integrate Magisk"
    sudo mkdir "$ROOT_MNT/sbin"
    sudo setfattr -n security.selinux -v "u:object_r:rootfs:s0" "$ROOT_MNT/sbin" || abort
    sudo chown root:root "$ROOT_MNT/sbin"
    sudo chmod 0700 "$ROOT_MNT/sbin"
    sudo cp "$WORK_DIR/magisk/magisk/"* "$ROOT_MNT/sbin/"
    sudo cp "$MAGISK_PATH" "$ROOT_MNT/sbin/magisk.apk" || abort
    sudo tee -a "$ROOT_MNT/sbin/loadpolicy.sh" <<EOF >/dev/null || abort
#!/system/bin/sh
mkdir -p /data/adb/magisk
cp /sbin/* /data/adb/magisk/
sync
chmod -R 755 /data/adb/magisk
restorecon -R /data/adb/magisk
for module in \$(ls /data/adb/modules); do
    if ! [ -f "/data/adb/modules/\$module/disable" ] && [ -f "/data/adb/modules/\$module/sepolicy.rule" ]; then
        /sbin/magiskpolicy --live --apply "/data/adb/modules/\$module/sepolicy.rule"
    fi
done
EOF

    sudo find "$ROOT_MNT/sbin" -type f -exec chmod 0755 {} \;
    sudo find "$ROOT_MNT/sbin" -type f -exec chown root:root {} \;
    sudo find "$ROOT_MNT/sbin" -type f -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort

    MAGISK_TMP_PATH=$(Gen_Rand_Str 14)
    echo "/dev/$MAGISK_TMP_PATH(/.*)?    u:object_r:magisk_file:s0" | sudo tee -a "$VENDOR_MNT/etc/selinux/vendor_file_contexts"
    echo '/data/adb/magisk(/.*)?   u:object_r:magisk_file:s0' | sudo tee -a "$VENDOR_MNT/etc/selinux/vendor_file_contexts"
    sudo LD_LIBRARY_PATH="../linker/$HOST_ARCH" "$WORK_DIR/magisk/magiskpolicy" --load "$VENDOR_MNT/etc/selinux/precompiled_sepolicy" --save "$VENDOR_MNT/etc/selinux/precompiled_sepolicy" --magisk || abort
    LOAD_POLICY_SVC_NAME=$(Gen_Rand_Str 12)
    PFD_SVC_NAME=$(Gen_Rand_Str 12)
    LS_SVC_NAME=$(Gen_Rand_Str 12)
    sudo tee -a "$SYSTEM_MNT/etc/init/hw/init.rc" <<EOF >/dev/null
on post-fs-data
    start adbd
    mkdir /dev/$MAGISK_TMP_PATH
    mount tmpfs tmpfs /dev/$MAGISK_TMP_PATH mode=0755
    copy /sbin/magisk64 /dev/$MAGISK_TMP_PATH/magisk64
    chmod 0755 /dev/$MAGISK_TMP_PATH/magisk64
    symlink ./magisk64 /dev/$MAGISK_TMP_PATH/magisk
    symlink ./magisk64 /dev/$MAGISK_TMP_PATH/su
    symlink ./magisk64 /dev/$MAGISK_TMP_PATH/resetprop
    copy /sbin/magisk32 /dev/$MAGISK_TMP_PATH/magisk32
    chmod 0755 /dev/$MAGISK_TMP_PATH/magisk32
    copy /sbin/magiskinit /dev/$MAGISK_TMP_PATH/magiskinit
    chmod 0755 /dev/$MAGISK_TMP_PATH/magiskinit
    copy /sbin/magiskpolicy /dev/$MAGISK_TMP_PATH/magiskpolicy
    chmod 0755 /dev/$MAGISK_TMP_PATH/magiskpolicy
    mkdir /dev/$MAGISK_TMP_PATH/.magisk 755
    mkdir /dev/$MAGISK_TMP_PATH/.magisk/mirror 0
    mkdir /dev/$MAGISK_TMP_PATH/.magisk/block 0
    mkdir /dev/$MAGISK_TMP_PATH/.magisk/worker 0
    copy /sbin/magisk.apk /dev/$MAGISK_TMP_PATH/stub.apk
    chmod 0644 /dev/$MAGISK_TMP_PATH/stub.apk
    rm /dev/.magisk_unblock
    exec_start $LOAD_POLICY_SVC_NAME
    start $PFD_SVC_NAME
    wait /dev/.magisk_unblock 40
    rm /dev/.magisk_unblock
    exec u:r:magisk:s0 0 0 -- /system/bin/mknod -m 0600 /dev/$MAGISK_TMP_PATH/.magisk/block/preinit b 8 0

service $LOAD_POLICY_SVC_NAME /system/bin/sh /sbin/loadpolicy.sh
    user root
    seclabel u:r:magisk:s0
    oneshot

service $PFD_SVC_NAME /dev/$MAGISK_TMP_PATH/magisk --post-fs-data
    user root
    seclabel u:r:magisk:s0
    oneshot

service $LS_SVC_NAME /dev/$MAGISK_TMP_PATH/magisk --service
    class late_start
    user root
    seclabel u:r:magisk:s0
    oneshot

on property:sys.boot_completed=1
    mkdir /data/adb/magisk 755
    copy /sbin/magisk.apk /data/adb/magisk/magisk.apk
    exec /dev/$MAGISK_TMP_PATH/magisk --boot-complete

on property:init.svc.zygote=restarting
    exec /dev/$MAGISK_TMP_PATH/magisk --zygote-restart

on property:init.svc.zygote=stopped
    exec /dev/$MAGISK_TMP_PATH/magisk --zygote-restart

EOF
    echo -e "Integrate Magisk done\n"
elif [ "$ROOT_SOL" = "kernelsu" ]; then
    echo "Integrate KernelSU"
    mv "$WORK_DIR/wsa/$ARCH/Tools/kernel" "$WORK_DIR/wsa/$ARCH/Tools/kernel_origin"
    cp "$WORK_DIR/kernelsu/kernel" "$WORK_DIR/wsa/$ARCH/Tools/kernel"
    echo -e "Integrate KernelSU done\n"
fi

echo "Add extra packages"
sudo cp -r "../$ARCH/system/"* "$SYSTEM_MNT" || abort
find "../$ARCH/system/priv-app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/priv-app/placeholder" -type d -exec chmod 0755 {} \;
find "../$ARCH/system/priv-app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/priv-app/placeholder" -type f -exec chmod 0644 {} \;
find "../$ARCH/system/priv-app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/priv-app/placeholder" -exec chown root:root {} \;
find "../$ARCH/system/priv-app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/priv-app/placeholder" -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
echo -e "Add extra packages done\n"

echo "Permissions management Netfree and Netspark security certificates"
find "../$ARCH/system/etc/security/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/etc/security/placeholder" -type d -exec chmod 0755 {} \;
find "../$ARCH/system/etc/security/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/etc/security/placeholder" -type f -exec chmod 0644 {} \;
find "../$ARCH/system/etc/security/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/etc/security/placeholder" -exec chown root:root {} \;
find "../$ARCH/system/etc/security/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/etc/security/placeholder" -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
echo -e "Permissions management Netfree and Netspark security certificates done\n"


if [ "$GAPPS_BRAND" != 'none' ]; then
    echo "Integrate $GAPPS_BRAND"
    find "$WORK_DIR/gapps/" -mindepth 1 -type d -exec sudo chmod 0755 {} \;
    find "$WORK_DIR/gapps/" -mindepth 1 -type d -exec sudo chown root:root {} \;
    file_list="$(find "$WORK_DIR/gapps/" -mindepth 1 -type f | cut -d/ -f5-)"
    for file in $file_list; do
        sudo chown root:root "$WORK_DIR/gapps/${file}"
        sudo chmod 0644 "$WORK_DIR/gapps/${file}"
    done

    if [ "$GAPPS_BRAND" = "OpenGApps" ]; then
        find "$WORK_DIR/gapps/" -maxdepth 1 -mindepth 1 -type d -not -path '*product' -exec sudo cp --preserve=all -r {} "$SYSTEM_MNT" \; || abort
    elif [ "$GAPPS_BRAND" = "MindTheGapps" ]; then
        sudo cp --preserve=all -r "$WORK_DIR/gapps/system_ext/"* "$SYSTEM_EXT_MNT/" || abort
        if [ -e "$SYSTEM_EXT_MNT/priv-app/SetupWizard" ]; then
            rm -rf "${SYSTEM_EXT_MNT:?}/priv-app/Provision"
        fi
    fi
    sudo cp --preserve=all -r "$WORK_DIR/gapps/product/"* "$PRODUCT_MNT" || abort

    find "$WORK_DIR/gapps/product/overlay" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/overlay/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:vendor_overlay_file:s0" {} \; || abort

    if [ "$GAPPS_BRAND" = "OpenGApps" ]; then
        find "$WORK_DIR/gapps/app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/app/placeholder" -type d -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
        find "$WORK_DIR/gapps/framework/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/framework/placeholder" -type d -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
        find "$WORK_DIR/gapps/priv-app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/priv-app/placeholder" -type d -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
        find "$WORK_DIR/gapps/app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/app/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
        find "$WORK_DIR/gapps/framework/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/framework/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
        find "$WORK_DIR/gapps/priv-app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/priv-app/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
        find "$WORK_DIR/gapps/etc/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/etc/placeholder" -type d -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
        find "$WORK_DIR/gapps/etc/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/etc/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
    else
        find "$WORK_DIR/gapps/product/app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/app/placeholder" -type d -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
        find "$WORK_DIR/gapps/product/etc/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/etc/placeholder" -type d -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
        find "$WORK_DIR/gapps/product/priv-app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/priv-app/placeholder" -type d -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
        find "$WORK_DIR/gapps/product/framework/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/framework/placeholder" -type d -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort

        find "$WORK_DIR/gapps/product/app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/app/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
        find "$WORK_DIR/gapps/product/etc/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/etc/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
        find "$WORK_DIR/gapps/product/priv-app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/priv-app/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
        find "$WORK_DIR/gapps/product/framework/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/framework/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
        find "$WORK_DIR/gapps/system_ext/etc/permissions/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_EXT_MNT/etc/permissions/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort

        sudo setfattr -n security.selinux -v "u:object_r:system_lib_file:s0" "$PRODUCT_MNT/lib" || abort
        find "$WORK_DIR/gapps/product/lib/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/lib/placeholder" -exec setfattr -n security.selinux -v "u:object_r:system_lib_file:s0" {} \; || abort
        find "$WORK_DIR/gapps/product/lib64/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/lib64/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:system_lib_file:s0" {} \; || abort
        find "$WORK_DIR/gapps/system_ext/priv-app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_EXT_MNT/priv-app/placeholder" -type d -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
        find "$WORK_DIR/gapps/system_ext/etc/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_EXT_MNT/etc/placeholder" -type d -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
        find "$WORK_DIR/gapps/system_ext/priv-app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_EXT_MNT/priv-app/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
    fi

    sudo LD_LIBRARY_PATH="../linker/$HOST_ARCH" "$WORK_DIR/magisk/magiskpolicy" --load "$VENDOR_MNT/etc/selinux/precompiled_sepolicy" --save "$VENDOR_MNT/etc/selinux/precompiled_sepolicy" "allow gmscore_app gmscore_app vsock_socket { create connect write read }" "allow gmscore_app device_config_runtime_native_boot_prop file read" "allow gmscore_app system_server_tmpfs dir search" "allow gmscore_app system_server_tmpfs file open" "allow gmscore_app system_server_tmpfs filesystem getattr" "allow gmscore_app gpu_device dir search" || abort
    echo -e "Integrate $GAPPS_BRAND done\n"
fi

if [ "$GAPPS_BRAND" != 'none' ]; then
    if [ "$NOFIX_PROPS" ]; then
        echo -e "Skip fix $GAPPS_BRAND prop!\n$GAPPS_PROPS_MSG1\n$GAPPS_PROPS_MSG2\n$GAPPS_PROPS_MSG3\n"
    else
        echo "Fix $GAPPS_BRAND prop"
        sudo python3 fixGappsProp.py "$ROOT_MNT" || abort
        echo -e "done\n"
    fi
fi
echo "Umount images"
sudo find "$ROOT_MNT" -exec touch -ht 200901010000.00 {} \;
sudo umount -v "$VENDOR_MNT"
sudo umount -v "$PRODUCT_MNT"
sudo umount -v "$SYSTEM_EXT_MNT"
sudo umount -v "$ROOT_MNT"
echo -e "done\n"

echo "Shrink images"
resize_img "$WORK_DIR/wsa/$ARCH/system.img" || abort
resize_img "$WORK_DIR/wsa/$ARCH/vendor.img" || abort
resize_img "$WORK_DIR/wsa/$ARCH/product.img" || abort
resize_img "$WORK_DIR/wsa/$ARCH/system_ext.img" || abort
echo -e "Shrink images done\n"

if [[ "$DOWN_WSA_MAIN_VERSION" -ge 2302 ]]; then
    echo "Convert images to vhdx"
    qemu-img convert -q -f raw -o subformat=fixed -O vhdx "$WORK_DIR/wsa/$ARCH/system_ext.img" "$WORK_DIR/wsa/$ARCH/system_ext.vhdx" || abort
    qemu-img convert -q -f raw -o subformat=fixed -O vhdx "$WORK_DIR/wsa/$ARCH/product.img" "$WORK_DIR/wsa/$ARCH/product.vhdx" || abort
    qemu-img convert -q -f raw -o subformat=fixed -O vhdx "$WORK_DIR/wsa/$ARCH/system.img" "$WORK_DIR/wsa/$ARCH/system.vhdx" || abort
    qemu-img convert -q -f raw -o subformat=fixed -O vhdx "$WORK_DIR/wsa/$ARCH/vendor.img" "$WORK_DIR/wsa/$ARCH/vendor.vhdx" || abort
    rm -f "$WORK_DIR/wsa/$ARCH/"*.img || abort
    echo -e "Convert images to vhdx done\n"
fi

echo "Remove signature and add scripts"
sudo rm -rf "${WORK_DIR:?}"/wsa/"$ARCH"/\[Content_Types\].xml "$WORK_DIR/wsa/$ARCH/AppxBlockMap.xml" "$WORK_DIR/wsa/$ARCH/AppxSignature.p7x" "$WORK_DIR/wsa/$ARCH/AppxMetadata" || abort
cp "$vclibs_PATH" "$xaml_PATH" "$WORK_DIR/wsa/$ARCH" || abort
cp "$UWPVCLibs_PATH" "$xaml_PATH" "$WORK_DIR/wsa/$ARCH" || abort
cp "../bin/$ARCH/makepri.exe" "$WORK_DIR/wsa/$ARCH" || abort
cp "../xml/priconfig.xml" "$WORK_DIR/wsa/$ARCH/xml/" || abort
cp ../installer/MakePri.ps1 "$WORK_DIR/wsa/$ARCH" || abort
cp ../installer/Install.ps1 "$WORK_DIR/wsa/$ARCH" || abort
cp ../installer/Run.bat "$WORK_DIR/wsa/$ARCH" || abort
find "$WORK_DIR/wsa/$ARCH" -maxdepth 1 -mindepth 1 -printf "%P\n" >"$WORK_DIR/wsa/$ARCH/filelist.txt" || abort
echo -e "Remove signature and add scripts done\n"

echo "Generate info"

if [[ "$ROOT_SOL" = "none" ]]; then
    name1=""
elif [ "$ROOT_SOL" = "magisk" ]; then
    name1="-with-magisk-$MAGISK_VERSION_NAME($MAGISK_VERSION_CODE)-$MAGISK_VER"
elif [ "$ROOT_SOL" = "kernelsu" ]; then
    name1="-with-$ROOT_SOL-$KERNELSU_VER"
fi
if [ "$GAPPS_BRAND" = "none" ]; then
    name2="-NoGApps"
else
    if [ "$GAPPS_BRAND" = "OpenGApps" ]; then
        name2=-$GAPPS_BRAND-${ANDROID_API_MAP[$ANDROID_API]}-${GAPPS_VARIANT}
    else
        name2=-$GAPPS_BRAND-${ANDROID_API_MAP[$ANDROID_API]}
    fi
    if [ "$GAPPS_BRAND" = "OpenGApps" ]; then
        echo -e "\033[0;31m:warning: Since $GAPPS_BRAND doesn't officially support Android 12.1 and 13 yet, lock the variant to pico!
          $GAPPS_BRAND may cause startup failure
        \033[0m"
    fi
fi
artifact_name=WSA_${WSA_VER}_${ARCH}_${WSA_REL}${name1}${name2}
if [ "$NOFIX_PROPS" = "yes" ]; then
    artifact_name+="-NoFixProps"
fi
if [ "$REMOVE_AMAZON" = "yes" ]; then
    artifact_name+="-RemovedAmazon"
fi
echo "$artifact_name"
echo "artifact=$artifact_name" >> "$GITHUB_OUTPUT"
echo -e "\nFinishing building...."
if [ -f "$OUTPUT_DIR" ]; then
    sudo rm -rf ${OUTPUT_DIR:?}
fi
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR"
fi
OUTPUT_PATH="${OUTPUT_DIR:?}/$artifact_name"
if [ "$COMPRESS_OUTPUT" ] || [ -n "$COMPRESS_FORMAT" ]; then
    mv "$WORK_DIR/wsa/$ARCH" "$WORK_DIR/wsa/$artifact_name"
    if [ -z "$COMPRESS_FORMAT" ]; then
        COMPRESS_FORMAT="7z"
    fi
    if [ -n "$COMPRESS_FORMAT" ]; then
        FILE_EXT=".$COMPRESS_FORMAT"
        if [ "$FILE_EXT" = ".xz" ]; then
            FILE_EXT=".tar$FILE_EXT"
        fi
        OUTPUT_PATH="$OUTPUT_PATH$FILE_EXT"
    fi
    rm -f "${OUTPUT_PATH:?}" || abort
    if [ "$COMPRESS_FORMAT" = "7z" ]; then
        echo "Compressing with 7z"
        7z a "${OUTPUT_PATH:?}" "$WORK_DIR/wsa/$artifact_name" || abort
    elif [ "$COMPRESS_FORMAT" = "xz" ]; then
        echo "Compressing with tar xz"
        if ! (tar -cP -I 'xz -9 -T0' -f "$OUTPUT_PATH" "$WORK_DIR/wsa/$artifact_name"); then
            echo "Out of memory? Trying again with single threads..."
            tar -cPJvf "$OUTPUT_PATH" "$WORK_DIR/wsa/$artifact_name" || abort
        fi
    elif [ "$COMPRESS_FORMAT" = "zip" ]; then
        echo "Compressing with zip"
        7z -tzip a "$OUTPUT_PATH" "$WORK_DIR/wsa/$artifact_name" || abort
    fi
else
    rm -rf "${OUTPUT_PATH:?}" || abort
    cp -r "$WORK_DIR/wsa/$ARCH" "$OUTPUT_PATH" || abort
fi
echo -e "done\n"

echo "Cleanup Work Directory"
sudo rm -rf "${WORK_DIR:?}"
echo "done"
