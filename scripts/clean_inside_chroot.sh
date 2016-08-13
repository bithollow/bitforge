#!/bin/bash

export LC_ALL=C LANGUAGE=C LANG=C

# install wifi driver
cd wifi_driver
./install.sh
cd ..

echo "before rootfs clean up"
du -sxh /*

# copy bh system
mkdir -p temp/ardupilot/ArduCopter
mkdir -p temp/bh_daemon
mkdir -p temp/lighttpd_fcgi/cgi

cp -a ardupilot/ArduCopter/ArduCopter.elf temp/ardupilot/ArduCopter/
cp -a bh_daemon/bh_daemon temp/bh_daemon/
cp -a -R bh_daemon/config temp/bh_daemon/
cp -a -R bh_daemon/script temp/bh_daemon/
cp -a lighttpd_fcgi/cgi/request.fcgi temp/lighttpd_fcgi/cgi/
cp -a -R lighttpd_fcgi/html  temp/lighttpd_fcgi/

rm -rf ardupilot
rm -rf bh_daemon
rm -rf lighttpd_fcgi
rm -rf hostapd_src
rm -rf pigpio
rm -rf wifi_driver
rm -rf WiringPi

mkdir -p ardupilot/ArduCopter
mkdir -p bh_daemon
mkdir -p lighttpd_fcgi/cgi

cp -a temp/ardupilot/ArduCopter/ArduCopter.elf ardupilot/ArduCopter/
cp -a temp/bh_daemon/bh_daemon bh_daemon/
cp -a -R temp/bh_daemon/config bh_daemon/
cp -a -R temp/bh_daemon/script bh_daemon/
cp -a temp/lighttpd_fcgi/cgi/request.fcgi lighttpd_fcgi/cgi/
cp -a -R temp/lighttpd_fcgi/html  lighttpd_fcgi/

rm -rf temp
rm -rf /tmp/ArduCopter.build

# remove dev tools
#apt-get autoremove --purge -y git build-essential libncurses5-dev bc file tree make gawk gcc
#apt-get autoremove
apt-get clean

echo "After rootfs clean up"
du -sxh /*

sync
