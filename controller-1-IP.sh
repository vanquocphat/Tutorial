#!/bin/bash -ex
#
source config.cfg

ifaces=/etc/network/interfaces
rm $ifaces
touch $ifaces
cat << EOF >> $ifaces

auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
address $CON_MGNT_IP
netmask $NETMASK_ADD

auto eth1
iface eth1 inet static
address $CON_EXT_IP
netmask $NETMASK_ADD
gateway $GATEWAY_IP
dns-nameservers 8.8.8.8
EOF

echo "controller" > /etc/hostname
hostname -F /etc/hostname
sleep 3
init 6





