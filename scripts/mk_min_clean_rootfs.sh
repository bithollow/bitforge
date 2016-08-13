#!/bin/bash

SOURCE_LIST=http://ftp.us.debian.org/debian

sudo debootstrap --foreign --no-check-gpg --include=ca-certificates --arch=armhf jessie rootfs ${SOURCE_LIST}
sudo cp $(which qemu-arm-static) rootfs/usr/bin
sudo chroot rootfs/ /debootstrap/debootstrap --second-stage --verbose
sudo sh -c 'echo deb ${SOURCE_LIST} jessie main > rootfs/etc/apt/sources.list'
sudo sh -c 'echo bithollow > rootfs/etc/hostname'
sudo sh -c 'echo -e 127.0.0.1\\tbithollow >> rootfs/etc/hosts'
sudo sh -c 'cat > rootfs/etc/network/interfaces << EOF
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet dhcp
auto wlan0
iface wlan0 inet manual
EOF
'
sudo mkdir -p rootfs/boot/firmware

sudo bash -c 'cat > rootfs/etc/fstab << EOF
proc /proc proc defaults 0 0
/dev/mmcblk0p1 /boot/firmware vfat defaults 0 0
EOF
'
sudo cp /etc/resolv.conf rootfs/etc

