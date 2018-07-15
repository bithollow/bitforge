#!/bin/bash

export LANGUAGE=C
export LC_ALL=C
export LANG=C

LOOP_DEV=loop2
IMG_SIZE=6979321856  #6.5GB
KERNEL_VER=4.6.5
RT_VER=preempt-rt9
DEVICE_TREE_BLOB=bcm2710-rpi-3-b.dtb
PATH_LINUX=../linux
PATH_FIRMWARE=../externals/firmware
PATH_PILE=../pile
PATH_RASPAP=..

dd if=/dev/zero of=rpi.img count=0 bs=1 seek=$IMG_SIZE

# 2GB for /firmware, 4GB for /
sudo sh -c 'cat << EOF | sfdisk --force rpi.img
unit: sectors
1 : start=     2048, size=   4194304, Id= c
2 : start=  4196352, size=   8388608, Id=83
EOF
'
sudo losetup /dev/$LOOP_DEV rpi.img -o $((2048*512)) --sizelimit $((4194304*512))
sudo mkfs.vfat -F 32 -n firmware /dev/$LOOP_DEV
sleep 1
sync
sudo losetup -d /dev/$LOOP_DEV
sudo losetup /dev/$LOOP_DEV rpi.img -o $((4196352*512)) --sizelimit $((8388608*512))
sudo mkfs.ext4 -L root /dev/$LOOP_DEV
sleep 1
sync
sudo losetup -d /dev/$LOOP_DEV

mkdir -p mnt/{firmware,root}

# prepare firmware partition
sudo mount -o loop,offset=$((2048*512)) rpi.img mnt/firmware
sudo mkdir -p mnt/firmware/overlays
sudo $PATH_LINUX/scripts/mkknlimg --dtok $PATH_LINUX/build/arch/arm/boot/zImage mnt/firmware/kernel.img
sudo cp $PATH_LINUX/build/arch/arm/boot/dts/${DEVICE_TREE_BLOB} mnt/firmware/
sudo cp -a --no-preserve=ownership $PATH_LINUX/build/arch/arm/boot/dts/overlays/*.dtbo mnt/firmware/overlays
sudo cp $PATH_FIRMWARE/boot/{*bin,*dat,*elf} mnt/firmware/

# create config.txt
sudo sh -c 'cat > mnt/firmware/config.txt << EOF
#kernel=kernel.img
core_freq=250
#sdram_freq=400
#over_voltage=0
#gpu_mem=16
dtparam=i2c_arm=on
dtparam=i2c_vc=on
dtparam=spi=on
enable_uart=1
dtoverlay=pi3-miniuart-bt
dtoverlay=i2c-rtc,ds1339
EOF
'

# create cmdline.txt
sudo sh -c 'cat > mnt/firmware/cmdline.txt << EOF
dwc_otg.fiq_enable=0 dwc_otg.fiq_fsm_enable=0 dwc_otg.nak_holdoff=0 dwc_otg.lpm_enable=0 console=serial0,115200 kgdboc=serial0,115200 root=/dev/mmcblk0p2 rw rootfstype=ext4 elevator=deadline fsck.repair=yes root wait
EOF
'

sudo umount mnt/firmware

# prepare root partition
sudo mount -o loop,offset=$((4196352*512)) rpi.img mnt/root
sudo rsync -a rootfs/ mnt/root/
sudo cp -a $PATH_FIRMWARE/hardfp/opt/vc mnt/root/opt/
sudo cp -a $PATH_LINUX/build/dist/lib/modules mnt/root/lib/
sudo cp -a $PATH_LINUX/build/dist/include/* mnt/root/usr/include
sudo cp $PATH_LINUX/build/.config mnt/root/boot/config-${KERNEL_VER}-${RT_VER}

sudo cp $(which qemu-arm-static) mnt/root/usr/bin

# copy rpi3 internal wifi adopter firmware
sudo mkdir -p mnt/root/lib/firmware/brcm
sudo tar jxf $PATH_PILE/brcmfmac43430-sdio.tar.bz2 -C mnt/root/lib/firmware/brcm

# enable rpi3 internal bt
sudo mkdir -p mnt/root/etc/firmware
sudo cp $PATH_PILE/BCM43430A1.hcd mnt/root/etc/firmware

sudo sh -c 'cat > mnt/root/lib/systemd/system/hciuart.service << EOF
[Unit]
Description=Configure Bluetooth Modems connected by UART
ConditionPathIsDirectory=/proc/device-tree/soc/gpio@7e200000/bt_pins
Before=bluetooth.service
After=dev-ttyS0.device

[Service]
Type=forking
ExecStart=/usr/bin/hciattach /dev/ttyS0 bcm43xx 921600 noflow -
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
'
sudo chroot mnt/root ln /lib/systemd/system/hciuart.service /etc/systemd/system/multi-user.target.wants

# install necessary packages
sudo sh -c 'cat > mnt/root/usr/sbin/policy-rc.d << EOF
#!/bin/sh
exit 101
EOF
'
sudo chroot mnt/root chmod a+x /usr/sbin/policy-rc.d
sudo mount -t devpts devpts mnt/root/dev/pts
sudo mount -t proc proc mnt/root/proc
sudo mount -t tmpfs tmpfs mnt/root/tmp
sudo cp -a $PATH_RASPAP/raspap-webgui mnt/root/tmp/
sudo -E chroot mnt/root apt-get update
sudo -E chroot mnt/root apt-get install bluez -y
sudo -E chroot mnt/root apt-get install lighttpd php-cgi hostapd dnsmasq dhcpcd5 wireless-tools -y
sudo -E chroot mnt/root apt-get clean
sudo chroot mnt/root bash /tmp/raspap-webgui/installers/common.sh
sudo chroot mnt/root rm -rf /usr/sbin/policy-rc.d
sudo umount mnt/root/proc
sudo umount mnt/root/dev/pts
sudo umount mnt/root/tmp

# enable hwclockfirst.service for ds1339
sudo sh -c 'cat > mnt/root/lib/systemd/system/hwclockfirst.service << EOF
[Unit]
Description=Synchronise Hardware Clock from System Clock
After=sysinit.target
Before=timers.target
DefaultDependencies=no
ConditionFileIsExecutable=!/usr/sbin/ntpd
ConditionFileIsExecutable=!/usr/sbin/openntpd
ConditionFileIsExecutable=!/usr/sbin/chrony
ConditionVirtualization=!container

[Service]
Type=oneshot
ExecStart=/sbin/hwclock -D --hctosys

[Install]
WantedBy=multi-user.target
'
sudo chroot mnt/root ln /lib/systemd/system/hwclockfirst.service /etc/systemd/system/multi-user.target.wants

# enable ardupilot.service
sudo cp $PATH_PILE/ArduCopter.elf mnt/root/sbin/ardupilot
sudo sh -c 'cat > mnt/root/lib/systemd/system/ardupilot.service << EOF
[Unit]
Description=ArduPilot on BH

[Service]
Type=idle
ExecStart=/sbin/ardupilot -A /dev/ttyAMA0 -C udp:10.0.0.255:14550:bcast 2>&1 > /var/log/ardupilot.log
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
'
sudo chroot mnt/root ln /lib/systemd/system/ardupilot.service /etc/systemd/system/multi-user.target.wants
sudo sh -c 'echo i2c-dev >> mnt/root/etc/modules'

# disable non-used services
# sudo chroot mnt/root systemctl disable getty@tty1.service
# sudo chroot mnt/root systemctl disable rsyslog.service
# sudo chroot mnt/root systemctl disable syslog.service

if [ -e mnt/root/usr/bin/qemu-arm-static ]; then
    sudo rm -rf mnt/root/usr/bin/qemu-arm-static
fi

if [ -e mnt/root/root/.bash_history ]; then
    sudo rm -rf mnt/root/root/.bash_history
fi

sudo umount mnt/root

sudo rm -f rpi.img.bz2
sync
# bzip2 -9 rpi.img
xz -9 rpi.img

# sudo sh -c 'bzcat rpi.img.bz2 > /dev/mmcblk0'
# sudo sh -c 'xzcat rpi.img.xz > /dev/mmcblk0'
