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

# shellcheck disable=SC2034
HOST_ARCH=$(uname -m)
cd "$(dirname "$0")" || exit 1
WORK_DIR=$(mktemp -d -t wsa-build-XXXXXXXXXX_) || exit 1

# lowerdir
ROOT_MNT_RO="$WORK_DIR/erofs"
VENDOR_MNT_RO="$ROOT_MNT_RO/vendor"
PRODUCT_MNT_RO="$ROOT_MNT_RO/product"
SYSTEM_EXT_MNT_RO="$ROOT_MNT_RO/system_ext"

# upperdir
ROOT_MNT_RW="$WORK_DIR/upper"
VENDOR_MNT_RW="$ROOT_MNT_RW/vendor"
PRODUCT_MNT_RW="$ROOT_MNT_RW/product"
SYSTEM_EXT_MNT_RW="$ROOT_MNT_RW/system_ext"
SYSTEM_MNT_RW="$ROOT_MNT_RW/system"

# merged
# shellcheck disable=SC2034
ROOT_MNT="$WORK_DIR/system_root_merged"
SYSTEM_MNT="$ROOT_MNT/system"
VENDOR_MNT="$ROOT_MNT/vendor"
PRODUCT_MNT="$ROOT_MNT/product"
SYSTEM_EXT_MNT="$ROOT_MNT/system_ext"

declare -A LOWER_PARTITION=(["zsystem"]="$ROOT_MNT_RO" ["vendor"]="$VENDOR_MNT_RO" ["product"]="$PRODUCT_MNT_RO" ["system_ext"]="$SYSTEM_EXT_MNT_RO")
declare -A UPPER_PARTITION=(["zsystem"]="$SYSTEM_MNT_RW" ["vendor"]="$VENDOR_MNT_RW" ["product"]="$PRODUCT_MNT_RW" ["system_ext"]="$SYSTEM_EXT_MNT_RW")
declare -A MERGED_PARTITION=(["zsystem"]="$ROOT_MNT" ["vendor"]="$VENDOR_MNT" ["product"]="$PRODUCT_MNT" ["system_ext"]="$SYSTEM_EXT_MNT")

DOWNLOAD_DIR=../download
DOWNLOAD_CONF_NAME=download.list
PYTHON_VENV_DIR="$(dirname "$PWD")/python3-env"
OUTPUT_DIR=../output
WSA_WORK_ENV="${WORK_DIR:?}/ENV"
if [ -f "$WSA_WORK_ENV" ]; then rm -f "${WSA_WORK_ENV:?}"; fi
touch "$WSA_WORK_ENV"
export WSA_WORK_ENV
abort() {
    [ "$1" ] && echo -e "ERROR: $1"
    echo "Build: an error has occurred, exit"
    exit 1
}
trap abort INT TERM

default() {
    ARCH=x64
    RELEASE_TYPE=retail
    MAGISK_VER=stable
    GAPPS_BRAND=MindTheGapps
    CUSTOM_MODEL=redfin
    ROOT_SOL=magisk
}

exit_with_message() {
    echo "ERROR: $1"
    exit 1
}

vhdx_to_raw_img() {
    qemu-img convert -q -f vhdx -O raw "$1" "$2" || return 1
    rm -f "$1" || return 1
}

mk_overlayfs() {
    local context own
    local workdir="$WORK_DIR/worker/$1"
    local lowerdir="$2"
    local upperdir="$3"
    local merged="$4"

    echo "mk_overlayfs: label $1
        lowerdir=$lowerdir
        upperdir=$upperdir
        workdir=$workdir
        merged=$merged"
    sudo mkdir -p -m 755 "$workdir" "$upperdir" "$merged"
    case "$1" in
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
    sudo mount -vt overlay overlay -olowerdir="$lowerdir",upperdir="$upperdir",workdir="$workdir" "$merged"
}

mk_erofs_umount() {
    sudo "../bin/$HOST_ARCH/mkfs.erofs" -zlz4hc -T1230768000 --chunksize=4096 --exclude-regex="lost+found" "$2".erofs "$1" || abort "Failed to make erofs image from $1"
    sudo umount -v "$1"
    sudo rm -f "$2"
    sudo mv "$2".erofs "$2"
    if [ "$3" ]; then
        sudo rm -rf "$3"
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

CUSTOM_MODEL_MAP=(
    "none"
    "sunfish"
    "bramble"
    "redfin"
    "barbet"
    "raven"
    "oriole"
    "bluejay"
    "panther"
    "cheetah"
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

ARGUMENT_LIST=(
    "arch:"
    "release-type:"
    "magisk-ver:"
    "gapps-brand:"
    "custom-model:"
    "root-sol:"
    "compress-format:"
    "remove-amazon"
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
        --custom-model      ) CUSTOM_MODEL="$2"; shift 2;;
        --root-sol          ) ROOT_SOL="$2"; shift 2 ;;
        --compress-format   ) COMPRESS_FORMAT="$2"; shift 2 ;;
        --remove-amazon     ) REMOVE_AMAZON="yes"; shift ;;
        --magisk-ver        ) MAGISK_VER="$2"; shift 2 ;;
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
check_list "$CUSTOM_MODEL" "Custom Model" "${CUSTOM_MODEL_MAP[@]}"
check_list "$ROOT_SOL" "Root Solution" "${ROOT_SOL_MAP[@]}"
check_list "$COMPRESS_FORMAT" "Compress Format" "${COMPRESS_FORMAT_MAP[@]}"

# shellcheck disable=SC1091
[ -f "$PYTHON_VENV_DIR/bin/activate" ] && {
    source "$PYTHON_VENV_DIR/bin/activate" || abort "Failed to activate virtual environment"
}
declare -A RELEASE_NAME_MAP=(["retail"]="Retail" ["RP"]="Release Preview" ["WIS"]="Insider Slow" ["WIF"]="Insider Fast")
RELEASE_NAME=${RELEASE_NAME_MAP[$RELEASE_TYPE]} || abort

echo -e "Build: RELEASE_TYPE=$RELEASE_NAME"

WSA_ZIP_PATH=$DOWNLOAD_DIR/wsa-$RELEASE_TYPE.zip
VCLibs_PATH="$DOWNLOAD_DIR/Microsoft.VCLibs.140.00_$ARCH.appx"
UWPVCLibs_PATH="$DOWNLOAD_DIR/Microsoft.VCLibs.140.00.UWPDesktop_$ARCH.appx"
xaml_PATH="$DOWNLOAD_DIR/Microsoft.UI.Xaml.2.8_$ARCH.appx"
MAGISK_ZIP=magisk-$MAGISK_VER.zip
MAGISK_PATH=$DOWNLOAD_DIR/$MAGISK_ZIP
GAPPS_ZIP_NAME=MindTheGapps-$ARCH-13.0.zip
GAPPS_PATH=$DOWNLOAD_DIR/$GAPPS_ZIP_NAME

update_ksu_zip_name() {
    KERNEL_VER="5.15.94.1"
    KERNELSU_ZIP_NAME=kernelsu-$ARCH-$KERNEL_VER.zip
    KERNELSU_PATH=$DOWNLOAD_DIR/$KERNELSU_ZIP_NAME
    KERNELSU_APK_PATH=$DOWNLOAD_DIR/KernelSU.apk
    KERNELSU_INFO="$KERNELSU_PATH.info"
}
update_gapps_zip_name() {
    GAPPS_ZIP_NAME=MindTheGapps-$ARCH-13.0.zip
    GAPPS_PATH=$DOWNLOAD_DIR/$GAPPS_ZIP_NAME
}
echo "Generate Download Links"
if [ "$DOWN_WSA" != "no" ]; then
    python3 generateWSALinks.py "$ARCH" "$RELEASE_TYPE" "$DOWNLOAD_DIR" "$DOWNLOAD_CONF_NAME" || abort
    # shellcheck disable=SC1090
    source "$WSA_WORK_ENV" || abort
else
    printf "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx\n" >> "$DOWNLOAD_DIR/$DOWNLOAD_CONF_NAME" || abort
    printf "  dir=%s\n" "$DOWNLOAD_DIR" >> "$DOWNLOAD_DIR/$DOWNLOAD_CONF_NAME" || abort
    printf "  out=Microsoft.VCLibs.140.00.UWPDesktop_x64.appx\n" >> "$DOWNLOAD_DIR/$DOWNLOAD_CONF_NAME" || abort
    printf "https://raw.githubusercontent.com/M1k3G0/Win10_LTSC_VP9_Installer/master/Microsoft.VCLibs.140.00_14.0.30704.0_x64__8wekyb3d8bbwe.appx\n" >> "$DOWNLOAD_DIR/$DOWNLOAD_CONF_NAME" || abort
    printf "  dir=%s\n" "$DOWNLOAD_DIR" >> "$DOWNLOAD_DIR/$DOWNLOAD_CONF_NAME" || abort
    printf "  out=Microsoft.VCLibs.140.00_x64.appx\n" >> "$DOWNLOAD_DIR/$DOWNLOAD_CONF_NAME" || abort
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
    python3 generateGappsLink.py "$ARCH" "$DOWNLOAD_DIR" "$DOWNLOAD_CONF_NAME" "$GAPPS_ZIP_NAME" || abort
fi
echo "Download Artifacts"
if ! aria2c --no-conf --log-level=info --log="$DOWNLOAD_DIR/aria2_download.log" -x16 -s16 -j5 -c -R -m0 --async-dns=false --check-integrity=true --continue=true --allow-overwrite=true --conditional-get=true -d"$DOWNLOAD_DIR" -i"$DOWNLOAD_DIR/$DOWNLOAD_CONF_NAME"; then
    echo "We have encountered an error while downloading files."
    exit 1
fi

echo "Extract WSA"
if [ -f "$WSA_ZIP_PATH" ]; then
    if ! python3 extractWSA.py "$ARCH" "$WSA_ZIP_PATH" "$WORK_DIR" "$WSA_WORK_ENV"; then
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
        if ! python3 extractMagisk.py "$ARCH" "$MAGISK_PATH" "$WORK_DIR"; then
            abort "Unzip Magisk failed, is the download incomplete?"
        fi
        # shellcheck disable=SC1090
        source "$WSA_WORK_ENV" || abort
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
    echo "Extract MindTheGapps"
    mkdir -p "$WORK_DIR/gapps" || abort
    if [ -f "$GAPPS_PATH" ]; then
        if ! unzip "$GAPPS_PATH" "system/*" -x "system/addon.d/*" "system/product/app/*Exchange*/*" "system/product/etc/default-permissions/*mtg*" "system/product/etc/permissions/*dialer*" "system/product/etc/sysconfig/*build*" "system/product/framework/*" "system/product/lib*/*" "system/product/priv-app/AndroidAuto*/*" "system/system_ext/priv-app/SetupWizard/*" -d "$WORK_DIR/gapps"; then
            abort "Unzip MindTheGapps failed, package is corrupted?"
        fi
        mv "$WORK_DIR/gapps/system/"* "$WORK_DIR/gapps" || abort
        rm -rf "${WORK_DIR:?}/gapps/system" || abort
        cp -r "../common/gapps/"* "$WORK_DIR/gapps" || abort
    else
        abort "The MindTheGapps zip package does not exist."
    fi
    echo -e "Extract done\n"
fi

echo "Convert vhdx to RAW image"
vhdx_to_raw_img "$WORK_DIR/wsa/$ARCH/system_ext.vhdx" "$WORK_DIR/wsa/$ARCH/system_ext.img" || abort
vhdx_to_raw_img "$WORK_DIR/wsa/$ARCH/product.vhdx" "$WORK_DIR/wsa/$ARCH/product.img" || abort
vhdx_to_raw_img "$WORK_DIR/wsa/$ARCH/system.vhdx" "$WORK_DIR/wsa/$ARCH/system.img" || abort
vhdx_to_raw_img "$WORK_DIR/wsa/$ARCH/vendor.vhdx" "$WORK_DIR/wsa/$ARCH/vendor.img" || abort
echo -e "Convert vhdx to RAW image done\n"
echo "Mount images"
sudo mkdir -p -m 755 "$ROOT_MNT_RO" || abort
sudo chown "0:0" "$ROOT_MNT_RO" || abort
sudo setfattr -n security.selinux -v "u:object_r:rootfs:s0" "$ROOT_MNT_RO" || abort
sudo "../bin/$HOST_ARCH/fuse.erofs" "$WORK_DIR/wsa/$ARCH/system.img" "$ROOT_MNT_RO" || abort 1
sudo "../bin/$HOST_ARCH/fuse.erofs" "$WORK_DIR/wsa/$ARCH/vendor.img" "$VENDOR_MNT_RO" || abort 1
sudo "../bin/$HOST_ARCH/fuse.erofs" "$WORK_DIR/wsa/$ARCH/product.img" "$PRODUCT_MNT_RO" || abort 1
sudo "../bin/$HOST_ARCH/fuse.erofs" "$WORK_DIR/wsa/$ARCH/system_ext.img" "$SYSTEM_EXT_MNT_RO" || abort 1
echo -e "done\n"
echo "Create overlayfs for EROFS"
mk_overlayfs system "$ROOT_MNT_RO" "$SYSTEM_MNT_RW" "$ROOT_MNT" || abort
mk_overlayfs vendor "$VENDOR_MNT_RO" "$VENDOR_MNT_RW" "$VENDOR_MNT" || abort
mk_overlayfs product "$PRODUCT_MNT_RO" "$PRODUCT_MNT_RW" "$PRODUCT_MNT" || abort
mk_overlayfs system_ext "$SYSTEM_EXT_MNT_RO" "$SYSTEM_EXT_MNT_RW" "$SYSTEM_EXT_MNT" || abort
echo -e "Create overlayfs for EROFS done\n"

if [ "$REMOVE_AMAZON" ]; then
    echo "Remove Amazon Appstore"
    rm -f "$WORK_DIR/wsa/$ARCH/apex/mado_release.apex"
    # Stub
    find "${PRODUCT_MNT:?}"/{apex,etc/*permissions} 2>/dev/null | grep -e mado | sudo xargs rm -rf
    echo -e "done\n"
fi

echo "Add device administration features"
sudo sed -i -e '/cts/a \ \ \ \ <feature name="android.software.device_admin" />' "$VENDOR_MNT/etc/permissions/windows.permissions.xml"
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
    chmod 0755 /debug_ramdisk/magisk64
    symlink ./magisk64 /debug_ramdisk/magisk
    symlink ./magisk64 /debug_ramdisk/su
    symlink ./magisk64 /debug_ramdisk/resetprop
    start adbd
    copy /dev/debug_ramdisk_mirror/magisk32 /debug_ramdisk/magisk32
    chmod 0755 /debug_ramdisk/magisk32
    copy /dev/debug_ramdisk_mirror/magiskinit /debug_ramdisk/magiskinit
    chmod 0755 /debug_ramdisk/magiskinit
    copy /dev/debug_ramdisk_mirror/magiskpolicy /debug_ramdisk/magiskpolicy
    chmod 0755 /debug_ramdisk/magiskpolicy
    mkdir /debug_ramdisk/.magisk
    mkdir /debug_ramdisk/.magisk/mirror 0
    mkdir /debug_ramdisk/.magisk/block 0
    mkdir /debug_ramdisk/.magisk/worker 0
    copy /dev/debug_ramdisk_mirror/stub.apk /debug_ramdisk/stub.apk
    chmod 0644 /debug_ramdisk/stub.apk
    copy /dev/debug_ramdisk_mirror/loadpolicy.sh /debug_ramdisk/loadpolicy.sh
    chmod 0755 /debug_ramdisk/loadpolicy.sh
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
            sudo setfattr -n security.selinux -v "u:object_r:system_file:s0" "$i" || abort
        fi
    done
    echo -e "Integrate Magisk done\n"
elif [ "$ROOT_SOL" = "kernelsu" ]; then
    echo "Copy KernelSU kernel"
    cp "$WORK_DIR/kernelsu/kernel" "$WORK_DIR/wsa/$ARCH/Tools/kernel"
    echo -e "Copy KernelSU kernel done\n"
    echo "Add auto-install script for KernelSU Manager"
    # Copy APK
    DAT_APP="$SYSTEM_MNT/data-app"
    sudo mkdir "$DAT_APP"
    sudo cp -f "$KERNELSU_APK_PATH" "$DAT_APP/"
    sudo chmod 0755 "$DAT_APP/"
    sudo chmod 0644 "$DAT_APP/KernelSU.apk"
    sudo find "$DAT_APP/" -exec chown root:root {} \;
    sudo find "$DAT_APP/" -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
    # Setup script
    KSU_PRE="$SYSTEM_MNT/bin/ksuinstall"
    sudo tee -a "$KSU_PRE" <<EOF >/dev/null || abort
#!/system/bin/sh
umask 0777
echo "\nKernelSU Install Manager"
if [ ! -e "/storage/emulated/0/.ksu_completed_\$(getprop ro.build.date.utc)" ]; then
    echo "\nInstalling KernelSU APK"
    pm install -i android -r /system/data-app/KernelSU.apk
    echo "\nLaunching KernelSU App"
    am start -n me.weishu.kernelsu/.ui.MainActivity
    touch "/storage/emulated/0/.ksu_completed_\$(getprop ro.build.date.utc)"
    echo "\nDone!\n"
else
    echo "\nKernelSU is installed.\n"
fi
EOF
    # Grant access
    sudo chmod 0755 "$KSU_PRE"
    sudo chown root:root "$KSU_PRE"
    sudo setfattr -n security.selinux -v "u:object_r:system_file:s0" "$KSU_PRE" || abort
    echo -e "Add KernelSU Manager done\n"
fi

echo "Add extra packages"
sudo cp -r "../common/system/"* "$SYSTEM_MNT" || abort
if [[ -d "../common/system/priv-app/" ]]; then
    find "../common/system/priv-app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo rm -rf "$SYSTEM_MNT/priv-app/placeholder/oat"
    find "../common/system/priv-app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/priv-app/placeholder" -type d -exec chmod 0755 {} \;
    find "../common/system/priv-app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/priv-app/placeholder" -type f -exec chmod 0644 {} \;
    find "../common/system/priv-app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/priv-app/placeholder" -exec chown root:root {} \;
    find "../common/system/priv-app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/priv-app/placeholder" -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
fi
echo -e "Add extra packages done\n"

echo "Permissions management Netfree and Netspark security certificates"
find "../common/system/etc/security/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/etc/security/placeholder" -type d -exec chmod 0755 {} \;
find "../common/system/etc/security/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/etc/security/placeholder" -type f -exec chmod 0644 {} \;
find "../common/system/etc/security/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/etc/security/placeholder" -exec chown root:root {} \;
find "../common/system/etc/security/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_MNT/etc/security/placeholder" -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
echo -e "Permissions management Netfree and Netspark security certificates done\n"

if [ "$GAPPS_BRAND" != 'none' ]; then
    echo "Integrate MindTheGapps"
    find "$WORK_DIR/gapps/" -mindepth 1 -type d -exec sudo chmod 0755 {} \;
    find "$WORK_DIR/gapps/" -mindepth 1 -type d -exec sudo chown root:root {} \;
    file_list="$(find "$WORK_DIR/gapps/" -mindepth 1 -type f | cut -d/ -f5-)"
    for file in $file_list; do
        sudo chown root:root "$WORK_DIR/gapps/${file}"
        sudo chmod 0644 "$WORK_DIR/gapps/${file}"
    done
    sudo cp --preserve=all -r "$WORK_DIR/gapps/system_ext/"* "$SYSTEM_EXT_MNT/" || abort
    if [ -e "$SYSTEM_EXT_MNT/priv-app/SetupWizard" ]; then
        rm -rf "${SYSTEM_EXT_MNT:?}/priv-app/Provision"
    fi
    sudo cp --preserve=all -r "$WORK_DIR/gapps/product/"* "$PRODUCT_MNT" || abort

    find "$WORK_DIR/gapps/product/overlay" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/overlay/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
    find "$WORK_DIR/gapps/product/etc/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/etc/placeholder" -type d -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
    find "$WORK_DIR/gapps/product/etc/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/etc/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
    #sudo setfattr -n security.selinux -v "u:object_r:system_file:s0" "$PRODUCT_MNT/framework" || abort
    find "$WORK_DIR/gapps/product/app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/app/placeholder" -type d -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
    find "$WORK_DIR/gapps/product/priv-app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/priv-app/placeholder" -type d -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
    #find "$WORK_DIR/gapps/product/framework/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/framework/placeholder" -type d -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
    find "$WORK_DIR/gapps/product/app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/app/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
    find "$WORK_DIR/gapps/product/priv-app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/priv-app/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
    #find "$WORK_DIR/gapps/product/framework/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/framework/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
    find "$WORK_DIR/gapps/system_ext/etc/permissions/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_EXT_MNT/etc/permissions/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
    #sudo setfattr -n security.selinux -v "u:object_r:system_lib_file:s0" "$PRODUCT_MNT/lib" || abort
    #find "$WORK_DIR/gapps/product/lib/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/lib/placeholder" -exec setfattr -n security.selinux -v "u:object_r:system_lib_file:s0" {} \; || abort
    #find "$WORK_DIR/gapps/product/lib64/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$PRODUCT_MNT/lib64/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:system_lib_file:s0" {} \; || abort
    find "$WORK_DIR/gapps/system_ext/priv-app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_EXT_MNT/priv-app/placeholder" -type d -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
    find "$WORK_DIR/gapps/system_ext/etc/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_EXT_MNT/etc/placeholder" -type d -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
    find "$WORK_DIR/gapps/system_ext/priv-app/" -maxdepth 1 -mindepth 1 -printf '%P\n' | xargs -I placeholder sudo find "$SYSTEM_EXT_MNT/priv-app/placeholder" -type f -exec setfattr -n security.selinux -v "u:object_r:system_file:s0" {} \; || abort
    sudo LD_LIBRARY_PATH="../linker/$HOST_ARCH" "$WORK_DIR/magisk/magiskpolicy" --load "$VENDOR_MNT/etc/selinux/precompiled_sepolicy" --save "$VENDOR_MNT/etc/selinux/precompiled_sepolicy" "allow gmscore_app gmscore_app vsock_socket { create connect write read }" "allow gmscore_app device_config_runtime_native_boot_prop file read" "allow gmscore_app system_server_tmpfs dir search" "allow gmscore_app system_server_tmpfs file open" "allow gmscore_app system_server_tmpfs filesystem getattr" "allow gmscore_app gpu_device dir search" "allow gmscore_app media_rw_data_file filesystem getattr" || abort
    echo -e "Integrate MindTheGapps done\n"
fi

if [[ "$CUSTOM_MODEL" != "none" ]]; then
    echo "Fix system props"
    # The first argument is prop path, second is product name (redfin), third is device model (Pixel 5)
    declare -A MODEL_NAME_MAP=(["sunfish"]="Pixel 4a" ["bramble"]="Pixel 4a (5G)" ["redfin"]="Pixel 5" ["barbet"]="Pixel 5a" ["raven"]="Pixel 6 Pro" ["oriole"]="Pixel 6" ["bluejay"]="Pixel 6a" ["panther"]="Pixel 7" ["cheetah"]="Pixel 7 Pro")
    MODEL_NAME="${MODEL_NAME_MAP[$CUSTOM_MODEL]}"
    sudo python3 fixGappsProp.py "$ROOT_MNT" "$CUSTOM_MODEL" "$MODEL_NAME" || abort
    # shellcheck disable=SC2002
    BUILD_ID=$(sudo cat "$SYSTEM_MNT/build.prop" | grep -e ro.build.id | cut -c 13-)
    if [[ "${#BUILD_ID}" != "15" ]]; then
        FIXED_BUILD_ID=$(echo "$BUILD_ID" | cut -c -15)
        echo "Fixed Build ID: $FIXED_BUILD_ID"
        # shellcheck disable=SC2086
        sudo find $ROOT_MNT/{system,system_ext,product,vendor} -name "build.prop" -exec sed -i -e "s/$BUILD_ID/$FIXED_BUILD_ID/g" {} \;
    fi
    echo -e "done\n"
    MODEL_NAME="${MODEL_NAME// /-}"
else
    MODEL_NAME="default"
fi

sudo find "$ROOT_MNT" -not -type l -exec touch -amt 200901010000.00 {} \;

echo "Create EROFS images"
mk_erofs_umount "$VENDOR_MNT" "$WORK_DIR/wsa/$ARCH/vendor.img" "$VENDOR_MNT_RW" || abort
mk_erofs_umount "$PRODUCT_MNT" "$WORK_DIR/wsa/$ARCH/product.img" "$PRODUCT_MNT_RW" || abort
mk_erofs_umount "$SYSTEM_EXT_MNT" "$WORK_DIR/wsa/$ARCH/system_ext.img" "$SYSTEM_EXT_MNT_RW" || abort
mk_erofs_umount "$ROOT_MNT" "$WORK_DIR/wsa/$ARCH/system.img" || abort
echo -e "Create EROFS images done\n"
echo "Umount images"
sudo umount -v "$VENDOR_MNT_RO"
sudo umount -v "$PRODUCT_MNT_RO"
sudo umount -v "$SYSTEM_EXT_MNT_RO"
sudo umount -v "$ROOT_MNT_RO"
echo -e "done\n"
echo "Convert images to vhdx"
qemu-img convert -q -f raw -o subformat=fixed -O vhdx "$WORK_DIR/wsa/$ARCH/system_ext.img" "$WORK_DIR/wsa/$ARCH/system_ext.vhdx" || abort
qemu-img convert -q -f raw -o subformat=fixed -O vhdx "$WORK_DIR/wsa/$ARCH/product.img" "$WORK_DIR/wsa/$ARCH/product.vhdx" || abort
qemu-img convert -q -f raw -o subformat=fixed -O vhdx "$WORK_DIR/wsa/$ARCH/system.img" "$WORK_DIR/wsa/$ARCH/system.vhdx" || abort
qemu-img convert -q -f raw -o subformat=fixed -O vhdx "$WORK_DIR/wsa/$ARCH/vendor.img" "$WORK_DIR/wsa/$ARCH/vendor.vhdx" || abort
rm -f "$WORK_DIR/wsa/$ARCH/"*.img || abort
echo -e "Convert images to vhdx done\n"

echo "Remove signature and add scripts"
sudo rm -rf "${WORK_DIR:?}"/wsa/"$ARCH"/\[Content_Types\].xml "$WORK_DIR/wsa/$ARCH/AppxBlockMap.xml" "$WORK_DIR/wsa/$ARCH/AppxSignature.p7x" "$WORK_DIR/wsa/$ARCH/AppxMetadata" || abort
cp "$VCLibs_PATH" "$xaml_PATH" "$WORK_DIR/wsa/$ARCH" || abort
cp "$UWPVCLibs_PATH" "$xaml_PATH" "$WORK_DIR/wsa/$ARCH" || abort
cp "../xml/priconfig.xml" "$WORK_DIR/wsa/$ARCH/xml/" || abort
if [[ "$ROOT_SOL" = "none" ]] && [[ "$GAPPS_BRAND" = "none" ]] && [[ "$REMOVE_AMAZON" == "yes" ]]; then
    sed -i -e 's/Start-Process\ "wsa:\/\/com.topjohnwu.magisk"//g' ../installer/Install.ps1
    sed -i -e 's/Start-Process\ "wsa:\/\/com.android.vending"//g' ../installer/Install.ps1
else
    if [[ "$ROOT_SOL" == "none" ]]; then
        sed -i -e 's/Start-Process\ "wsa:\/\/com.topjohnwu.magisk"//g' ../installer/Install.ps1
    elif [[ "$ROOT_SOL" = "kernelsu" ]]; then
        sed -i -e 's/wsa:\/\/com.topjohnwu.magisk/https:\/\/github.com\/YT-Advanced\/WSA-Script\/blob\/main\/Guides\/KernelSU.md/g' ../installer/Install.ps1
    elif [[ "$MAGISK_VER" = "delta" ]]; then
        sed -i -e 's/com.topjohnwu.magisk/io.github.huskydg.magisk/g' ../installer/Install.ps1
    elif [[ "$MAGISK_VER" = "alpha" ]]; then
        sed -i -e 's/com.topjohnwu.magisk/io.github.vvb2060.magisk/g' ../installer/Install.ps1
    fi
    if [[ "$GAPPS_BRAND" = "none" ]] && [[ "$REMOVE_AMAZON" != "yes" ]]; then
        sed -i -e 's/com.android.vending/com.amazon.venezia/g' ../installer/Install.ps1
    elif [[ "$GAPPS_BRAND" = "none" ]]; then
        sed -i -e 's/Start-Process\ "wsa:\/\/com.android.vending"//g' ../installer/Install.ps1
    fi
fi
cp ../installer/Install.ps1 "$WORK_DIR/wsa/$ARCH" || abort
find "$WORK_DIR/wsa/$ARCH" -not -path "*/pri*" -not -path "*/xml*" -printf "%P\n" | sed -e 's/\//\\/g' -e '/^$/d' > "$WORK_DIR/wsa/$ARCH/filelist.txt" || abort
find "$WORK_DIR/wsa/$ARCH/pri" -printf "%P\n" | sed -e 's/^/pri\\/' -e '/^$/d' > "$WORK_DIR/wsa/$ARCH/filelist-pri.txt" || abort
find "$WORK_DIR/wsa/$ARCH/xml" -printf "%P\n" | sed -e 's/^/xml\\/' -e '/^$/d' >> "$WORK_DIR/wsa/$ARCH/filelist-pri.txt" || abort
cp "../bin/$ARCH/makepri.exe" "$WORK_DIR/wsa/$ARCH" || abort
echo "makepri.exe" >> "$WORK_DIR/wsa/$ARCH/filelist-pri.txt" || abort
cp ../installer/MakePri.ps1 "$WORK_DIR/wsa/$ARCH" || abort
cp ../installer/Run.bat "$WORK_DIR/wsa/$ARCH" || abort
echo -e "Remove signature and add scripts done\n"

echo "Generate info"
if [[ "$ROOT_SOL" = "none" ]]; then
    name1=""
elif [ "$ROOT_SOL" = "magisk" ]; then
    name1="-with-Magisk-$MAGISK_VERSION_NAME-$MAGISK_VER"
elif [ "$ROOT_SOL" = "kernelsu" ]; then
    name1="-with-KernelSU-$KERNELSU_VER"
fi
if [ "$GAPPS_BRAND" = "none" ]; then
    name2="-NoGApps"
else
    name2=-MindTheGapps-13.0
fi
if [[ "$MODEL_NAME" != "default" ]]; then
    name3="-as-$MODEL_NAME"
fi
artifact_name=WSA_${WSA_VER}_${ARCH}_${WSA_REL}${name1}${name2}${name3}
if [ "$REMOVE_AMAZON" = "yes" ]; then
    artifact_name+="-RemovedAmazon"
fi
echo "$artifact_name"
echo "artifact=$artifact_name" >> "$GITHUB_OUTPUT"
echo -e "\nFinishing building...."
mkdir -p "$OUTPUT_DIR"
OUTPUT_PATH="${OUTPUT_DIR:?}/$artifact_name"
mv "$WORK_DIR/wsa/$ARCH" "$WORK_DIR/wsa/$artifact_name"
if [ "$COMPRESS_FORMAT" = "7z" ]; then
    OUTPUT_PATH="$OUTPUT_PATH.7z"
    echo "Compressing with 7z"
    7z a "${OUTPUT_PATH:?}" "$WORK_DIR/wsa/$artifact_name" || abort
elif [ "$COMPRESS_FORMAT" = "xz" ]; then
    OUTPUT_PATH="$OUTPUT_PATH.tar.xz"
    echo "file_ext=.tar.xz" >> "$GITHUB_OUTPUT"
    echo "Compressing with tar xz"
    if ! (tar -cP -I 'xz -9 -T0' -f "$OUTPUT_PATH" "$WORK_DIR/wsa/$artifact_name"); then
        echo "Out of memory? Trying again with single threads..."
        tar -cPJvf "$OUTPUT_PATH" "$WORK_DIR/wsa/$artifact_name" || abort
    fi
elif [ "$COMPRESS_FORMAT" = "zip" ]; then
    echo "Compressing with zip later..."
    echo "file_ext=.zip" >> "$GITHUB_OUTPUT"
    cp -r "$WORK_DIR/wsa/$artifact_name" "$OUTPUT_PATH" || abort
    touch "$OUTPUT_PATH/apex/.gitkeep" || abort
fi
echo -e "Done\n"
