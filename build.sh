#!/usr/bin/env bash

if [ -z "$SUDO_USER" ]; then
    echo "This script must be run with sudo."
    exit 1
fi

set -e
trap 'echo Error: in $0 on line $LINENO' ERR  



# Function to get the user's country (shell-only version)
get_current_country() {
    # Use curl and jq to get the country code
    local country=$(curl -s "https://api.country.is" | jq -r '.country')

    # Handle potential errors (e.g., if curl or jq fail, or the API is down)
    if [ -z "$country" ]; then
        echo "Error: Could not determine country. Assuming non-China." >&2
        country="XX"  # Use a non-China code as a fallback
    fi

    echo "$country"
}

# Function to download a file, using a mirror if in China
download_file() {
    local url="$1"
    local save_path="$2"
    local country=$(get_current_country)

    local download_url
    if [ "$country" = "CN" ]; then
        download_url="https://fastgit.czyt.tech/$url"
        echo "Using FastGit mirror: $download_url"
    else
        download_url="$url"
        echo "Using original URL: $download_url"
    fi

    if wget "$download_url" -O "$save_path"; then
        return 0
    else
        echo "Error: download failed $download_url" >&2
        return 1
    fi
}

function setup_mountpoint() {
    local mountpoint="$1"


    echo "run setup mount point in $(pwd)"
    if [ ! -c /dev/mem ]; then
        mknod -m 660 /dev/mem c 1 1
        chown root:kmem /dev/mem
    fi

    mount dev-live -t devtmpfs "$mountpoint/dev"
    mount devpts-live -t devpts -o nodev,nosuid "$mountpoint/dev/pts"
    mount proc-live -t proc "$mountpoint/proc"
    mount sysfs-live -t sysfs "$mountpoint/sys"
    mount securityfs -t securityfs "$mountpoint/sys/kernel/security"
    # Provide more up to date apparmor features, matching target kernel
    # cgroup2 mount for LP: 1944004
    mount -t cgroup2 none "$mountpoint/sys/fs/cgroup"
    mount -t tmpfs none "$mountpoint/tmp"
    mount -t tmpfs none "$mountpoint/var/lib/apt/lists"
    mount -t tmpfs none "$mountpoint/var/cache/apt"
    mv "$mountpoint"/etc/resolv.conf{,.tmp}
    cp /etc/resolv.conf "$mountpoint/etc/resolv.conf"
    mv "$mountpoint"/etc/nsswitch.conf{,.tmp}
    sed 's/systemd//g' "$mountpoint/etc/nsswitch.conf.tmp" > "$mountpoint/etc/nsswitch.conf"
}

function teardown_mountpoint() {
    # Reverse the operations from setup_mountpoint
    local mountpoint
    mountpoint=$(realpath "$1")
    echo "run teardown mount point in $(pwd)"
    # ensure we have exactly one trailing slash, and escape all slashes for awk
    mountpoint_match=$(echo "$mountpoint" | sed -e 's,/$,,; s,/,\\/,g;')'\/'
    # sort -r ensures that deeper mountpoints are unmounted first
    awk </proc/self/mounts "\$2 ~ /$mountpoint_match/ { print \$2 }" | LC_ALL=C sort -r | while IFS= read -r submount; do
        mount --make-private "$submount"
        umount "$submount"
    done
    mv "$mountpoint"/etc/resolv.conf{.tmp,}
    mv "$mountpoint"/etc/nsswitch.conf{.tmp,}
    if [ -f $mountpoint/usr/bin/qemu-aarch64-static ]; then
        rm -rf $mountpoint/usr/bin/qemu-aarch64-static
    fi
    
}

function build_image() {
    board="$1"
    addon=$2

    init_build_dir=$(pwd)

    local dis_relese_url="https://api.github.com/repos/Joshua-Riek/ubuntu-rockchip/releases/latest"
    local image_latest_tag=$(curl -s "$dis_relese_url" | grep -m 1 '"tag_name":' | awk -F '"' '{print $4}')
    if [ -n "$image_latest_tag" ]; then
        echo "The ubuntu-rockchip latest release tag: $image_latest_tag"
        local image_download_url="https://github.com/Joshua-Riek/ubuntu-rockchip/releases/download/$image_latest_tag/ubuntu-24.04-preinstalled-desktop-arm64-$board.img.xz"
        local image_save_name="ubuntu-24.04-preinstalled-desktop-arm64-$board.img.xz"

        if [ ! -d dist ]; then
            mkdir dist || echo "Dist directory creation failed."
        fi

        cd dist || exit 0
        echo "current working in $(pwd)"

        if [ -f "$image_save_name" ];then
            echo "$image_save_name already exists. Skipping download."
        else
            echo "$image_save_name not found. Downloading..."
            download_file "$image_download_url"  "$image_save_name"
        fi

        echo "Check if the image exists"
        if [ -f "$image_save_name" ]; then
            echo "Image exists, unpacking it..."

            MOUNT_POINT="/mnt/ubuntu-img"
            IMG_PATH="$init_build_dir/dist/ubuntu-24.04-preinstalled-desktop-arm64-$board.img"

            if [ ! -f "$IMG_PATH" ]; then
                xz -d "$image_save_name"
                rm -rf "$image_save_name"
            fi

            mkdir -p $MOUNT_POINT

            export DEBIAN_FRONTEND=noninteractive

            # Override localisation settings to address a perl warning
            export LC_ALL=C

            LOOP_DEVICE=$(losetup -fP --show "$IMG_PATH")
            partprobe "$LOOP_DEVICE"

            ROOT_PARTITION=$(lsblk -lno NAME "$LOOP_DEVICE" | grep -E "^$(basename "$LOOP_DEVICE")p.*" | head -n 1 | sed 's/^/\/dev\//')

            if [ -z "$ROOT_PARTITION" ]; then
                echo "No partitions found in the loop device"
                losetup -d "$LOOP_DEVICE"
                exit 1
            fi

            mount "$ROOT_PARTITION" $MOUNT_POINT
            setup_mountpoint $MOUNT_POINT

            echo "Image mounted. Returning to source directory..."
            cd "$init_build_dir"
            echo "current working in $(pwd)"

            echo "Copying QEMU binary..."
            apt-get install qemu-user-static binfmt-support -y

            if [ ! -f $MOUNT_POINT/usr/bin/qemu-aarch64-static ]; then
                cp /usr/bin/qemu-aarch64-static $MOUNT_POINT/usr/bin/qemu-aarch64-static
            fi

            echo "Copying systemd service definitions and related scripts..."
            cp -r ./overlay/usr/lib/systemd/system/* $MOUNT_POINT/usr/lib/systemd/system/
            cp -r ./overlay/usr/lib/scripts/* $MOUNT_POINT/usr/lib/scripts

            echo "Copying Holomotion theme and wallpapers..."
            cp -r ./overlay/usr/share/plymouth/themes/holomotion $MOUNT_POINT/usr/share/plymouth/themes/
            mkdir -p "$MOUNT_POINT/usr/share/backgrounds"
            cp "./overlay/usr/share/backgrounds/holomotion01.jpeg" $MOUNT_POINT/usr/share/backgrounds/holomotion01.jpeg

            echo "Copying user scripts and shell extensions to the mounted filesystem..."
            mkdir -p $MOUNT_POINT/tmp
            cp -r "./postscripts" $MOUNT_POINT/tmp/
            cp -r ./overlay/usr/share/shellextensions $MOUNT_POINT/tmp/shellextensions/
            cp -f "./chroot/chroot-run.sh" $MOUNT_POINT/tmp/chroot-run.sh


            echo "Entering chroot environment to execute chroot-run.sh..."
            chroot $MOUNT_POINT /usr/bin/qemu-aarch64-static /bin/bash /tmp/chroot-run.sh "$addon"

            echo "enter the dist dir again.."
            teardown_mountpoint $MOUNT_POINT

            umount $MOUNT_POINT || echo "Failed to unmount $MOUNT_POINT"
            losetup -d "$LOOP_DEVICE" || echo "Failed to detach loop device $LOOP_DEVICE"

            echo "change to resource dir"
            cd "$init_build_dir"
            echo "current working in $(pwd)"

            mkdir -p ./images
            img_file="$init_build_dir/images/ubuntu-24.04-preinstalled-desktop-arm64-$board.img"
            if [ -n "$addon" ];then
                img_file="$init_build_dir/images/ubuntu-24.04-preinstalled-desktop-arm64-$board-with-$addon.img"
            fi
            echo "moving $IMG_PATH to $img_file "
            mv "$IMG_PATH" "$img_file"
            check_and_handle_image_split "$img_file"
        fi
    fi
}

function check_and_handle_image_split(){
    img_file=$1
    echo -e "\nCompressing $(basename "${img_file}.xz")\n"
    xz -6 --force --keep --quiet --threads=0 "${img_file}"
    rm -f "${img_file}"
    echo "check whether to process img.xz"

    COMPRESSED_FILE="${img_file}.xz"
    FILE_SIZE=$(stat -c%s "${COMPRESSED_FILE}")
    MAX_SIZE=$((2 * 1024 * 1024 * 1024))

    echo "the file size of $COMPRESSED_FILE is $FILE_SIZE"

    if [ $FILE_SIZE -gt $MAX_SIZE ]; then
        echo "the compressed file is large, begin to split img to parts"
        SPLIT_SIZE=2000M
        split -b $SPLIT_SIZE --numeric-suffixes=1 -d "${COMPRESSED_FILE}" "${COMPRESSED_FILE}.part"
        # Extract the directory and basename of the compressed file
        COMPRESSED_DIR=$(dirname "${COMPRESSED_FILE}")
        COMPRESSED_BASENAME=$(basename "${COMPRESSED_FILE}")
        find "${COMPRESSED_DIR}" -name "${COMPRESSED_BASENAME}.part*" -print0 | while IFS= read -r -d '' part; do
            sha256sum "$part" > "$part.sha256"
        done

        rm -rf "${COMPRESSED_FILE}"
    else
        echo "no need to process compressed image, calculate the checksum."
        sha256sum "$COMPRESSED_FILE" > "$COMPRESSED_FILE.sha256"
    fi

}


board="$1"
addon="$2"

build_image "$board" "$addon"
