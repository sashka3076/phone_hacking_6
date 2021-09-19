#!/bin/bash
#
# Bridge setup for reverse tethering
# adi@apple.com, May 2012
#

# Use this if you know the interface, and it is stable
SRC_IF=$1
DST_IF=$2
BRG_IF=$3

echo "Nuking $BRG_IF"
/sbin/ifconfig $BRG_IF destroy

echo "Creating $BRG_IF"
/sbin/ifconfig $BRG_IF create

echo "Adding $SRC_IF and $DST_IF as member interfaces to $BRG_IF"
/sbin/ifconfig $BRG_IF addm $SRC_IF
/sbin/ifconfig $BRG_IF addm $DST_IF

sleep 1

echo "Nuking active configurations for $SRC_IF and $DST_IF"
/usr/sbin/ipconfig set $SRC_IF NONE
/usr/sbin/ipconfig set $SRC_IF NONE-V6
/usr/sbin/ipconfig set $DST_IF NONE
/usr/sbin/ipconfig set $DST_IF NONE-V6

sleep 1

echo "Setting up active configurations $BRG_IF"
/usr/sbin/ipconfig set $BRG_IF DHCP
/usr/sbin/ipconfig set $BRG_IF AUTOMATIC-V6
