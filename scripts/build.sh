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

HOST_ARCH=$(uname -m)
cd "$(dirname "$0")" || exit 1
# export TMPDIR=$(dirname "$PWD")/WORK_DIR_
if [ "$TMPDIR" ] && [ ! -d "$TMPDIR" ]; then
    mkdir -p "$TMPDIR"
fi
WORK_DIR=$(mktemp -d -t wsa-build-XXXXXXXXXX_) || exit 1

# lowerdir
ROOT_MNT_RO="$WORK_DIR/erofs"
VENDOR_MNT_RO="$ROOT_MNT_RO/vendor"
PRODUCT_MNT_RO="$ROOT_MNT_RO/product"
SYSTEM_EXT_MNT_RO="$ROOT_MNT_RO/system_ext"

# merged
ROOT_MNT="$WORK_DIR/system_root_merged"
SYSTEM_MNT="$ROOT_MNT/system"
VENDOR_MNT="$ROOT_MNT/vendor"
PRODUCT_MNT="$ROOT_MNT/product"
SYSTEM_EXT_MNT="$ROOT_MNT/system_ext"

declare -A LOWER_PARTITION=(["zsystem"]="$ROOT_MNT_RO" ["vendor"]="$VENDOR_MNT_RO" ["product"]="$PRODUCT_MNT_RO" ["system_ext"]="$SYSTEM_EXT_MNT_RO")
declare -A MERGED_PARTITION=(["zsystem"]="$ROOT_MNT" ["vendor"]="$VENDOR_MNT" ["product"]="$PRODUCT_MNT" ["system_ext"]="$SYSTEM_EXT_MNT")
DOWNLOAD_DIR=../download
DOWNLOAD_CONF_NAME=download.list
PYTHON_VENV_DIR="$(dirname "$PWD")/python3-env"
EROFS_USE_FUSE=1
umount_clean() {
    if [ -d "$ROOT_MNT" ] || [ -d "$ROOT_MNT_RO" ]; then
        echo "Cleanup Mount Directory"
        for PART in "${LOWER_PARTITION[@]}"; do
            sudo umount -v "$PART"
        done
        for PART in "${MERGED_PARTITION[@]}"; do
            sudo umount -v "$PART"
        done
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
    if [ "$(which python)" == "$PYTHON_VENV_DIR/bin/python" ]; then
        echo "deactivate python3 venv"
        deactivate
    fi
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
    [ "$1" ] && echo -e "ERROR: $1"
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
    ROOT_SOL=magisk
}

exit_with_message() {
    echo "ERROR: $1"
    exit 1
}

resize_img() {
    sudo e2fsck -pf "$1" || return 1
    if [ "$2" ]; then
        sudo resize2fs "$1" "$2" || return 1
    else
        sudo resize2fs -M "$1" || return 1
    fi
    return 0
}

vhdx_to_raw_img() {
    qemu-img convert -q -f vhdx -O raw "$1" "$2" || return 1
    rm -f "$1" || return 1
}

mk_overlayfs() {
    local lowerdir="$1"
    local upperdir workdir merged context own
    merged="$3"
    case "$2" in
        system)
            upperdir="$WORK_DIR/upper/$2"
            workdir="$WORK_DIR/worker/$2"
            ;;
        *)
            upperdir="$WORK_DIR/upper/system/$2"
            workdir="$WORK_DIR/worker/system/$2"
            ;;
    esac
    echo "mk_overlayfs: label $2
        lowerdir=$lowerdir
        upperdir=$upperdir
        workdir=$workdir
        merged=$merged"
    sudo mkdir -p -m 755 "$workdir" "$upperdir" "$merged"
    case "$2" in
        vendor)
            context="u:object_r:vendor_file:s0"
            own="0:2000"
            ;;
        system)
            context="u:object_r:rootfs:s0"
            own="0:0"
            ;;
        *)
            context="u:object_r:system_file:s0"
            own="0:0"
            ;;
    esac
    sudo chown -R "$own" "$upperdir" "$workdir" "$merged"
    sudo setfattr -n security.selinux -v "$context" "$upperdir"
    sudo setfattr -n security.selinux -v "$context" "$workdir"
    sudo setfattr -n security.selinux -v "$context" "$merged"
    sudo mount -vt overlay overlay -ouserxattr,lowerdir="$lowerdir",upperdir="$upperdir",workdir="$workdir" "$merged"
}

mk_erofs_umount() {
    sudo "../bin/$HOST_ARCH/mkfs.erofs" -zlz4hc -T1230768000 --chunksize=4096 --exclude-regex="lost+found" "$2".erofs "$1" || abort "Failed to make erofs image from $1"
    sudo umount -v "$1"
    sudo rm -f "$2"
    sudo mv "$2".erofs "$2"
}

ro_ext4_img_to_rw() {
    resize_img "$1" "$(($(du --apparent-size -sB512 "$1" | cut -f1) * 2))"s || return 1
    e2fsck -fp -E unshare_blocks "$1" || return 1
    resize_img "$1" || return 1
    return 0
}

mount_erofs() {
    if [ "$EROFS_USE_FUSE" ]; then
        sudo "../bin/$HOST_ARCH/fuse.erofs" "$1" "$2" || return 1
    else
        sudo mount -v -t erofs -o ro,loop "$1" "$2" || return 1
    fi
}

# workaround for Debian
# In Debian /usr/sbin is not in PATH and some utilities in there are in use
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
    "alpha"
)

GAPPS_BRAND_MAP=(
    "MindTheGapps"
    "none"
)

ROOT_SOL_MAP=(
    "magisk"
    "kernelsu"
    "none"
)

COMPRESS_FORMAT_MAP=(
    "7z"
    "zip"
    "xz"
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

ARGUMENT_LIST=(
    "arch:"
    "release-type:"
    "magisk-ver:"
    "gapps-brand:"
    "nofix-props"
    "root-sol:"
    "compress-format:"
    "remove-amazon"
    "compress"
    "debug"
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
        --nofix-props       ) NOFIX_PROPS="yes"; shift ;;
        --root-sol          ) ROOT_SOL="$2"; shift 2 ;;
        --compress-format   ) COMPRESS_FORMAT="$2"; shift 2 ;;
        --remove-amazon     ) REMOVE_AMAZON="yes"; shift ;;
        --compress          ) COMPRESS_OUTPUT="yes"; shift ;;
        --magisk-ver        ) MAGISK_VER="$2"; shift 2 ;;
        --debug             ) DEBUG="on"; shift ;;
        --skip-download-wsa ) DOWN_WSA="no"; shift ;;
        --                  ) shift; break;;
   esac
done

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
check_list "$ROOT_SOL" "Root Solution" "${ROOT_SOL_MAP[@]}"
check_list "$COMPRESS_FORMAT" "Compress Format" "${COMPRESS_FORMAT_MAP[@]}"

if [ "$DEBUG" ]; then
    set -x
fi

# shellcheck disable=SC1091
[ -f "$PYTHON_VENV_DIR/bin/activate" ] && {
    source "$PYTHON_VENV_DIR/bin/activate" || abort "Failed to activate virtual environment, please re-run install_deps.sh"
}
declare -A RELEASE_NAME_MAP=(["retail"]="Retail" ["RP"]="Release Preview" ["WIS"]="Insider Slow" ["WIF"]="Insider Fast")
declare -A ANDROID_API_MAP=(["33"]="13.0")
RELEASE_NAME=${RELEASE_NAME_MAP[$RELEASE_TYPE]} || abort

echo -e "Build: RELEASE_TYPE=$RELEASE_NAME"

WSA_ZIP_PATH=$DOWNLOAD_DIR/wsa-$RELEASE_TYPE.zip
vclibs_PATH="$DOWNLOAD_DIR/Microsoft.VCLibs.140.00_$ARCH.appx"
UWPVCLibs_PATH="$DOWNLOAD_DIR/Microsoft.VCLibs.140.00.UWPDesktop_$ARCH.appx"
xaml_PATH="$DOWNLOAD_DIR/Microsoft.UI.Xaml.2.8_$ARCH.appx"
MAGISK_ZIP=magisk-$MAGISK_VER.zip
MAGISK_PATH=$DOWNLOAD_DIR/$MAGISK_ZIP
ANDROID_API=33
GAPPS_ZIP_NAME=$GAPPS_BRAND-$ARCH-${ANDROID_API_MAP[$ANDROID_API]}.zip
GAPPS_PATH=$DOWNLOAD_DIR/$GAPPS_ZIP_NAME
WSA_MAIN_VER=0
update_ksu_zip_name() {
    KERNEL_VER="5.10.117.2"
    if [ "$WSA_MAIN_VER" -ge "2303" ]; then
        KERNEL_VER="5.15.78.1"
    fi
    if [ "$WSA_MAIN_VER" -ge "2304" ]; then
        KERNEL_VER="5.15.94.1"
    fi
    KERNELSU_ZIP_NAME=kernelsu-$ARCH-$KERNEL_VER.zip
    KERNELSU_PATH=$DOWNLOAD_DIR/$KERNELSU_ZIP_NAME
    KERNELSU_INFO="$KERNELSU_PATH.info"
}
if [ "$DOWN_WSA" != "no" ]; then
    echo "Generate Download Links"
    python3 generateWSALinks.py "$ARCH" "$RELEASE_TYPE" "$DOWNLOAD_DIR" "$DOWNLOAD_CONF_NAME" || abort
    # shellcheck disable=SC1090
    source "$WSA_WORK_ENV" || abort
else
    WSA_MAIN_VER=$(python3 getWSAMainVersion.py "$ARCH" "$WSA_ZIP_PATH")
fi
if [ "$ROOT_SOL" = "magisk" ] || [ "$GAPPS_BRAND" != "none" ]; then
    python3 generateMagiskLink.py "$MAGISK_VER" "$DOWNLOAD_DIR" "$DOWNLOAD_CONF_NAME" || abort
fi
if [ "$ROOT_SOL" = "kernelsu" ]; then
    update_ksu_zip_name
    python3 generateKernelSULink.py "$ARCH" "$DOWNLOAD_DIR" "$DOWNLOAD_CONF_NAME" "$KERNEL_VER" "$KERNELSU_ZIP_NAME" || abort
    # shellcheck disable=SC1090
    source "$WSA_WORK_ENV" || abort
    # shellcheck disable=SC2153
    echo "KERNELSU_VER=$KERNELSU_VER" >"$KERNELSU_INFO"
fi
if [ "$GAPPS_BRAND" != "none" ]; then
    update_gapps_zip_name
    python3 generateGappsLink.py "$ARCH" "$DOWNLOAD_DIR" "$DOWNLOAD_CONF_NAME" "$ANDROID_API" "$GAPPS_ZIP_NAME" || abort
fi
 echo "Download Artifacts"
if ! aria2c --no-conf --log-level=info --log="$DOWNLOAD_DIR/aria2_download.log" -x16 -s16 -j5 -c -R -m0 --async-dns=false --check-integrity=true --continue=true --allow-overwrite=true --conditional-get=true -d"$DOWNLOAD_DIR" -i"$DOWNLOAD_DIR/$DOWNLOAD_CONF_NAME"; then
    echo "We have encountered an error while downloading files."
    exit 1
fi

echo "Extract WSA"
if [ -f "$WSA_ZIP_PATH" ]; then
    if ! python3 extractWSA.py "$ARCH" "$WSA_ZIP_PATH" "$WORK_DIR" "$WSA_WORK_ENV"; then
        CLEAN_DOWNLOAD_WSA=1
        abort "Unzip WSA failed, is the download incomplete?"
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
            CLEAN_DOWNLOAD_MAGISK=1
            abort "Unzip Magisk failed, is the download incomplete?"
        fi
        # shellcheck disable=SC1090
        source "$WSA_WORK_ENV" || abort
        if [ "$MAGISK_VERSION_CODE" -lt 26000 ] && [ "$MAGISK_VER" != "delta" ]; then
            abort "Please install Magisk 26.0+"
        fi
        sudo chmod +x "../linker/$HOST_ARCH/linker64" || abort
        sudo patchelf --set-interpreter "../linker/$HOST_ARCH/linker64" "$WORK_DIR/magisk/magiskpolicy" || abort
        chmod +x "$WORK_DIR/magisk/magiskpolicy" || abort
    else
        echo "The Magisk zip package does not exist, rename it to magisk-debug.zip and put it in the download folder."
        exit 1
    fi
    echo -e "done\n"
fi

if [ "$ROOT_SOL" = "kernelsu" ]; then
    update_ksu_zip_name
    echo "Extract KernelSU"
    # shellcheck disable=SC1090
    source "${KERNELSU_INFO:?}" || abort
    if ! unzip "$KERNELSU_PATH" -d "$WORK_DIR/kernelsu"; then
        CLEAN_DOWNLOAD_KERNELSU=1
        abort "Unzip KernelSU failed, package is corrupted?"
    fi
    if [ "$ARCH" = "x64" ]; then
        mv "$WORK_DIR/kernelsu/bzImage" "$WORK_DIR/kernelsu/kernel"
    elif [ "$ARCH" = "arm64" ]; then
        mv "$WORK_DIR/kernelsu/Image" "$WORK_DIR/kernelsu/kernel"
    fi
    echo -e "done\n"
fi

if [ "$GAPPS_BRAND" != 'none' ]; then
    update_gapps_zip_name
    echo "Extract $GAPPS_BRAND"
    mkdir -p "$WORK_DIR/gapps" || abort
    if [ -f "$GAPPS_PATH" ]; then
        if ! unzip "$GAPPS_PATH" "system/*" -x "system/addon.d/*" "system/system_ext/priv-app/SetupWizard/*" -d "$WORK_DIR/gapps"; then
             CLEAN_DOWNLOAD_GAPPS=1
            abort "Unzip MindTheGapps failed, package is corrupted?"
        fi
        mv "$WORK_DIR/gapps/system/"* "$WORK_DIR/gapps" || abort
        rm -rf "${WORK_DIR:?}/gapps/system" || abort
        cp -r "../$ARCH/gapps/"* "$WORK_DIR/gapps" || abort
    else
        abort "The $GAPPS_BRAND zip package does not exist."
    fi
    echo -e "Extract done\n"
fi

if [[ "$WSA_MAIN_VER" -ge 2302 ]]; then
    echo "Convert vhdx to RAW image"
    vhdx_to_raw_img "$WORK_DIR/wsa/$ARCH/system_ext.vhdx" "$WORK_DIR/wsa/$ARCH/system_ext.img" || abort
    vhdx_to_raw_img "$WORK_DIR/wsa/$ARCH/product.vhdx" "$WORK_DIR/wsa/$ARCH/product.img" || abort
    vhdx_to_raw_img "$WORK_DIR/wsa/$ARCH/system.vhdx" "$WORK_DIR/wsa/$ARCH/system.img" || abort
    vhdx_to_raw_img "$WORK_DIR/wsa/$ARCH/vendor.vhdx" "$WORK_DIR/wsa/$ARCH/vendor.img" || abort
    echo -e "Convert vhdx to RAW image done\n"
fi
if [[ "$WSA_MAIN_VER" -ge 2304 ]]; then
    echo "Mount images"
    sudo mkdir -p -m 755 "$ROOT_MNT_RO" || abort
    sudo chown "0:0" "$ROOT_MNT_RO" || abort
    sudo setfattr -n security.selinux -v "u:object_r:rootfs:s0" "$ROOT_MNT_RO" || abort
    mount_erofs "$WORK_DIR/wsa/$ARCH/system.img" "$ROOT_MNT_RO" || abort
    mount_erofs "$WORK_DIR/wsa/$ARCH/vendor.img" "$VENDOR_MNT_RO" || abort
    mount_erofs "$WORK_DIR/wsa/$ARCH/product.img" "$PRODUCT_MNT_RO" || abort
    mount_erofs "$WORK_DIR/wsa/$ARCH/system_ext.img" "$SYSTEM_EXT_MNT_RO" || abort
    echo -e "done\n"
    echo "Create overlayfs for EROFS"
    mk_overlayfs "$ROOT_MNT_RO" system "$ROOT_MNT" || abort 
    mk_overlayfs "$VENDOR_MNT_RO" vendor "$VENDOR_MNT" || abort
    mk_overlayfs "$PRODUCT_MNT_RO" product "$PRODUCT_MNT" || abort
    mk_overlayfs "$SYSTEM_EXT_MNT_RO" system_ext "$SYSTEM_EXT_MNT" || abort
    echo -e "Create overlayfs for EROFS done\n"
elif [[ "$WSA_MAIN_VER" -ge 2302 ]]; then
    echo "Remove read-only flag for read-only EXT4 image"
    ro_ext4_img_to_rw "$WORK_DIR/wsa/$ARCH/system_ext.img" || abort
    ro_ext4_img_to_rw "$WORK_DIR/wsa/$ARCH/product.img" || abort
    ro_ext4_img_to_rw "$WORK_DIR/wsa/$ARCH/system.img" || abort
    ro_ext4_img_to_rw "$WORK_DIR/wsa/$ARCH/vendor.img" || abort
    echo -e "Remove read-only flag for read-only EXT4 image done\n"
fi
if [[ "$WSA_MAIN_VER" -lt 2304 ]]; then
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
fi
if [ "$REMOVE_AMAZON" ]; then
    echo "Remove Amazon Appstore"
    find "${PRODUCT_MNT:?}"/{etc/permissions,etc/sysconfig,framework,priv-app} 2>/dev/null | grep -e amazon -e venezia | sudo xargs rm -rf
    find "${SYSTEM_EXT_MNT:?}"/{etc/*permissions,framework,priv-app} 2>/dev/null | grep -e amazon -e venezia | sudo xargs rm -rf
    rm -f "$WORK_DIR/wsa/$ARCH/apex/mado_release.apex"
    echo -e "done\n"
fi

echo "Add device administration features"
sudo sed -i -e '/cts/a \ \ \ \ <feature name="android.software.device_admin" />' -e '/print/i \ \ \ \ <feature name="android.software.managed_users" />' "$VENDOR_MNT/etc/permissions/windows.permissions.xml"
sudo setfattr -n security.selinux -v "u:object_r:vendor_configs_file:s0" "$VENDOR_MNT/etc/permissions/windows.permissions.xml" || abort
echo -e "done\n"

if [ "$ROOT_SOL" = 'magisk' ]; then
    echo "Integrate Magisk"
    sudo cp "$WORK_DIR/magisk/magisk/"* "$ROOT_MNT/debug_ramdisk/"
    sudo cp "$MAGISK_PATH" "$ROOT_MNT/debug_ramdisk/stub.apk" || abort
    sudo tee -a "$ROOT_MNT/debug_ramdisk/loadpolicy.sh" <<EOF >/dev/null || abort
#!/system/bin/sh
MAGISKTMP=/debug_ramdisk
export MAGISKTMP
mkdir -p /data/adb/magisk
cp \$MAGISKTMP/* /data/adb/magisk/
sync
chmod -R 755 /data/adb/magisk
restorecon -R /data/adb/magisk
MAKEDEV=1 \$MAGISKTMP/magisk --preinit-device 2>&1
RULESCMD=""
for r in \$MAGISKTMP/.magisk/preinit/*/sepolicy.rule; do
  [ -f "\$r" ] || continue
  RULESCMD="\$RULESCMD --apply \$r"
done
\$MAGISKTMP/magiskpolicy --live \$RULESCMD 2>&1
EOF
    sudo find "$ROOT_MNT/debug_ramdisk" -type f -exec chmod 0711 {} \;
    sudo find "$ROOT_MNT/debug_ramdisk" -type f -exec chown root:root {} \;
    sudo find "$ROOT_MNT/debug_ramdisk" -type f -exec setfattr -n security.selinux -v "u:object_r:magisk_file:s0" {} \; || abort
    echo "/debug_ramdisk(/.*)?    u:object_r:magisk_file:s0" | sudo tee -a "$VENDOR_MNT/etc/selinux/vendor_file_contexts"
    echo '/data/adb/magisk(/.*)?   u:object_r:magisk_file:s0' | sudo tee -a "$VENDOR_MNT/etc/selinux/vendor_file_contexts"
    sudo LD_LIBRARY_PATH="../linker/$HOST_ARCH" "$WORK_DIR/magisk/magiskpolicy" --load "$VENDOR_MNT/etc/selinux/precompiled_sepolicy" --save "$VENDOR_MNT/etc/selinux/precompiled_sepolicy" --magisk || abort
    NEW_INITRC_DIR=$SYSTEM_MNT/etc/init/hw
    sudo tee -a "$SYSTEM_MNT/etc/init/hw/init.rc" <<EOF >/dev/null
on post-fs-data
    mkdir /dev/debug_ramdisk_mirror
    mount none /debug_ramdisk /dev/debug_ramdisk_mirror bind
    mount none none /dev/debug_ramdisk_mirror private
    mount tmpfs magisk /debug_ramdisk mode=0755
    copy /dev/debug_ramdisk_mirror/magisk64 /debug_ramdisk/magisk64
    chmod 0711 /debug_ramdisk/magisk64
    symlink ./magisk64 /debug_ramdisk/magisk
    symlink ./magisk64 /debug_ramdisk/su
    symlink ./magisk64 /debug_ramdisk/resetprop
    start adbd
    copy /dev/debug_ramdisk_mirror/magisk32 /debug_ramdisk/magisk32
    chmod 0711 /debug_ramdisk/magisk32
    copy /dev/debug_ramdisk_mirror/magiskinit /debug_ramdisk/magiskinit
    chmod 0711 /debug_ramdisk/magiskinit
    copy /dev/debug_ramdisk_mirror/magiskpolicy /debug_ramdisk/magiskpolicy
    chmod 0711 /debug_ramdisk/magiskpolicy
    mkdir /debug_ramdisk/.magisk
    mkdir /debug_ramdisk/.magisk/mirror 0
    mkdir /debug_ramdisk/.magisk/block 0
    mkdir /debug_ramdisk/.magisk/worker 0
    copy /dev/debug_ramdisk_mirror/stub.apk /debug_ramdisk/stub.apk
    chmod 0644 /debug_ramdisk/stub.apk
    copy /dev/debug_ramdisk_mirror/loadpolicy.sh /debug_ramdisk/loadpolicy.sh
    chmod 0711 /debug_ramdisk/loadpolicy.sh
    umount /dev/debug_ramdisk_mirror
    rmdir /dev/debug_ramdisk_mirror
    exec u:r:magisk:s0 0 0 -- /system/bin/sh /debug_ramdisk/loadpolicy.sh
    exec u:r:magisk:s0 0 0 -- /debug_ramdisk/magisk --post-fs-data

on property:vold.decrypt=trigger_restart_framework
    exec u:r:magisk:s0 0 0 -- /debug_ramdisk/magisk --service

on nonencrypted
    exec u:r:magisk:s0 0 0 -- /debug_ramdisk/magisk --service

on property:sys.boot_completed=1
    exec u:r:magisk:s0 0 0 --  /debug_ramdisk/magisk --boot-complete

on property:init.svc.zygote=stopped
    exec u:r:magisk:s0 0 0 -- /debug_ramdisk/magisk --zygote-restart
EOF

for i in "$NEW_INITRC_DIR"/*; do
    if [[ "$i" =~ init.zygote.+\.rc ]]; then
        echo "Inject zygote restart $i"
        sudo awk -i inplace '{if($0 ~ /service zygote /){print $0;print "    exec u:r:magisk:s0 0 0 -- /debug_ramdisk/magisk --zygote-restart";a="";next}} 1' "$i"
    fi
done

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

    if [ "$GAPPS_BRAND" = "MindTheGapps" ]; then
        sudo cp --preserve=all -r "$WORK_DIR/gapps/system_ext/"* "$SYSTEM_EXT_MNT/" || abort
        if [ -e "$SYSTEM_EXT_MNT/priv-app/SetupWizard" ]; then
            rm -rf "${SYSTEM_EXT_MNT:?}/priv-app/Provision"
        fi
    fi
    sudo cp --preserve=all -r "$WORK_DIR/gapps/product/"* "$PRODUCT_MNT" || abort

    find "$WORK_DIR/gapps/product/overlay" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/overlay/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:vendor_overlay_file:s0" {} \; || abort
    find "$WORK_DIR/gapps/product/etc/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/etc/placeholder" -type d -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
    find "$WORK_DIR/gapps/product/etc/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/etc/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort

    if [ "$GAPPS_BRAND" = "MindTheGapps" ]; then
        find "$WORK_DIR/gapps/product/app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/app/placeholder" -type d -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
        find "$WORK_DIR/gapps/product/priv-app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/priv-app/placeholder" -type d -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
        find "$WORK_DIR/gapps/product/framework/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/framework/placeholder" -type d -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort

        find "$WORK_DIR/gapps/product/app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/app/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
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

    sudo LD_LIBRARY_PATH="../linker/$HOST_ARCH" "$WORK_DIR/magisk/magiskpolicy" --load "$VENDOR_MNT/etc/selinux/precompiled_sepolicy" --save "$VENDOR_MNT/etc/selinux/precompiled_sepolicy" "allow gmscore_app gmscore_app vsock_socket { create connect write read }" "allow gmscore_app device_config_runtime_native_boot_prop file read" "allow gmscore_app system_server_tmpfs dir search" "allow gmscore_app system_server_tmpfs file open" "allow gmscore_app system_server_tmpfs filesystem getattr" "allow gmscore_app gpu_device dir search" "allow gmscore_app media_rw_data_file filesystem getattr" || abort
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

if [[ "$WSA_MAIN_VER" -ge 2304 ]]; then
    echo "Create EROFS images"
    mk_erofs_umount "$VENDOR_MNT" "$WORK_DIR/wsa/$ARCH/vendor.img" || abort
    mk_erofs_umount "$PRODUCT_MNT" "$WORK_DIR/wsa/$ARCH/product.img" || abort
    mk_erofs_umount "$SYSTEM_EXT_MNT" "$WORK_DIR/wsa/$ARCH/system_ext.img" || abort
    mk_erofs_umount "$ROOT_MNT" "$WORK_DIR/wsa/$ARCH/system.img" || abort
    echo -e "Create EROFS images done\n"
    echo "Umount images"
    sudo umount -v "$VENDOR_MNT_RO"
    sudo umount -v "$PRODUCT_MNT_RO"
    sudo umount -v "$SYSTEM_EXT_MNT_RO"
    sudo umount -v "$ROOT_MNT_RO"
    echo -e "done\n"
else
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
fi

if [[ "$WSA_MAIN_VER" -ge 2302 ]]; then
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
    name2=-$GAPPS_BRAND-${ANDROID_API_MAP[$ANDROID_API]}
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
        echo "file_ext=$FILE_EXT" >> "$GITHUB_OUTPUT"
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
