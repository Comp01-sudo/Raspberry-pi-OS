#!/usr/bin/env bash
#
# Kali Linux ARM build-script for Raspberry Pi 2 1.2/3/4/400 (64-bit)
# Source: https://gitlab.com/kalilinux/build-scripts/kali-arm
#
# This is a supported device - which you can find pre-generated images on: https://www.kali.org/get-kali/
# More information: https://www.kali.org/docs/arm/raspberry-pi-64-bit/
#

# Hardware model
hw_model=${hw_model:-"raspberry-pi"}
# Architecture (arm64, armhf, armel)
architecture=${architecture:-"arm64"}
# Desktop manager (xfce, gnome, i3, kde, lxde, mate, e17 or none)
desktop=${desktop:-"gnome"}

# Load default base_image configs
source ./load_base.sh

# Network configs
basic_network
add_interface eth0

# Third stage
cat <<EOF >> "${work_dir}"/third-stage
status_stage3 'Copy rpi services'
cp -p /bsp/services/rpi/*.service /etc/systemd/system/

status_stage3 'Script mode wlan monitor START/STOP'
install -m755 /bsp/scripts/{monstart,monstop} /usr/bin/

status_stage3 'Install the kernel packages'
echo "deb http://http.re4son-kernel.com/re4son kali-pi main" > /etc/apt/sources.list.d/re4son.list
wget -qO /etc/apt/trusted.gpg.d/kali_pi-archive-keyring.gpg https://re4son-kernel.com/keys/http/kali_pi-archive-keyring.gpg
eatmydata apt-get update
eatmydata apt-get install -y ${re4son_pkgs}

status_stage3 'Copy script for handling wpa_supplicant file'
install -m755 /bsp/scripts/copy-user-wpasupplicant.sh /usr/bin/

status_stage3 'Enable copying of user wpa_supplicant.conf file'
systemctl enable copy-user-wpasupplicant

status_stage3 'Enabling ssh by putting ssh or ssh.txt file in /boot'
systemctl enable enable-ssh

status_stage3 'Enable login over serial (No password)'
echo "T0:23:respawn:/sbin/agetty -L ttyAMA0 115200 vt100" >> /etc/inittab

status_stage3 'Fixup wireless-regdb signature'
update-alternatives --set regulatory.db /lib/firmware/regulatory.db-upstream
EOF

# Run third stage
include third_stage

# Compile Raspberry Pi userland
include rpi_userland

# Clean system
include clean_system

# Calculate the space to create the image and create
make_image

# Create the disk partitions
status "Create the disk partitions"
parted -s "${image_dir}/${image_name}.img" mklabel msdos
parted -s "${image_dir}/${image_name}.img" mkpart primary fat32 1MiB "${bootsize}"MiB
parted -s -a minimal "${image_dir}/${image_name}.img" mkpart primary "$fstype" "${bootsize}"MiB 100%

# Set the partition variables
make_loop
# Create file systems
mkfs_partitions
# Make fstab.
make_fstab
# Configure Raspberry Pi firmware (before rsync)
include rpi_firmware
# Fix up bluetooth
sed -i 's/ttyAMA0/serial0/g' "${work_dir}"/boot/cmdline.txt
echo 'dtparam=krnbt=on' | tee -a "${work_dir}"/boot/config.txt

# Create the dirs for the partitions and mount them
status "Create the dirs for the partitions and mount them"
mkdir -p "${base_dir}"/root/
mount "${rootp}" "${base_dir}"/root
mkdir -p "${base_dir}"/root/boot
mount "${bootp}" "${base_dir}"/root/boot

status "Rsyncing rootfs into image file"
rsync -HPavz -q --exclude boot "${work_dir}"/ "${base_dir}"/root/
sync

status "Rsyncing boot into image file (/boot)"
rsync -rtx -q "${work_dir}"/boot "${base_dir}"/root
sync

# Load default finish_image configs
include finish_image
