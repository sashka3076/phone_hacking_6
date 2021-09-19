#!/bin/bash
FILE_VERSION="0.1"
hw_model=$(sysctl hw.model|awk '/:/ {print $2}')
echo "HW Model is : $hw_model"
IPv6=$(ifconfig awdl0 | awk '/inet/ {print $2}' | awk -F : '{print $6}' | awk -F % '{print $1}')
en0Interface=$(ifconfig en0 | awk '/inet6/ {print $2}'| awk -F : '{print $6}' | awk -F % '{print $1}')
en1Interface=$(ifconfig en1 | awk '/inet6/ {print $2}'| awk -F : '{print $6}' | awk -F % '{print $1}')
#To find out interface for ATV vs iDevice
if [ ! -z $en1Interface ]; then
    interface="en1"
    /usr/local/bin/airplayutil logging AirPlayReceiverPlatform:level=chatty
    /usr/local/bin/airplayutil logging AirPlayReceiverServer:level=chatty
    /usr/local/bin/airplayutil logging AirPlayReceiverPlatform:level=chatty
    /usr/local/bin/airplayutil logging AirPlayJitterBuffer:level=chatty
    /usr/local/bin/airplayutil logging APAdvertiser*:level=info
else 
    interface="en0"
    /usr/local/bin/airplayutil logging APBrowser*:level=info
    /usr/local/bin/airplayutil logging APBonjour*:level=info
fi
echo "Interface is " $interface

if [ ! -z $IPv6 ]; then
	echo "AWDL interface is up"
    LOGDIR=/tmp/awdl_logs
else
    IPv6=$interface
    LOGDIR=/tmp/infra_logs
	echo "ERROR: AWDL interface is down"
fi

rm -rf $LOGDIR
mkdir $LOGDIR
mkdir $LOGDIR/CrashReporter2
DATE=$(date +"%Y%m%d%H%M%S")
#netdiagnose start ; sleep 15
#apple80211 awdl0 -quiet -logf="vv set" -outfile=$LOGDIR/awdlFamily_$IPv6.pcap -dlog &

# If AWDL-capable and script exists, start AWDL logging
if [ -f apple80211AWDL.sh ] && [ ! -z $IPv6 ];then
	apple80211AWDL.sh -d $LOGDIR &
fi
#/usr/sbin/discoveryutil -p loglevel Everything 
echo "Installing profile"
profilectl install! /AppleInternal/Library/WiFi/Profiles/MegaWifi\ Profile.mobileconfig
if [ ! -z $IPv6 ];then
    while true;do date;apple80211 -awdl; sleep 2; done > $LOGDIR/awdlState.txt &
    tcpdump -C 50 -W 3 -npi awdl0 -w $LOGDIR/awdl0_tcpdump_$IPv6.pcap & 
    syslog -w -F std.3 -k Sender sharingd > $LOGDIR/sharingd_$IPv6.txt & 
	
fi
# Include "INFO" level logs in syslog outputs
syslog -c mDNSResponder -i

login -f mobile defaults write com.apple.wirelessproxd.debug ShouldLog YES
login -f mobile defaults write com.apple.MobileBluetooth.debug DiagnosticMode YES
login -f mobile defaults write com.apple.MobileBluetooth.debug DefaultLevel Info
login -f mobile defaults write com.apple.MobileBluetooth.debug LEDiscovery -dict DebugLevel Debug
login -f mobile defaults write com.apple.MobileBluetooth.debug HCITraces -dict StackDebugEnabled TRUE
login -f mobile /usr/bin/killall -USR1 BTServer
login -f mobile /usr/bin/killall -9 wirelessproxd
tcpdump -C 50 -W 3 -n -i iptap -w $LOGDIR/awdl0_tcpdump_iptap_$IPv6.pcap &
tcpdump -C 50 -W 3 -i pktap -w $LOGDIR/awdl0_tcpdump_pktap_$IPv6.pcap &
syslog -w -F std.3 > $LOGDIR/syslog_$IPv6.txt &
#
/usr/bin/killall -INFO mDNSResponder
/usr/bin/killall -TSTP mDNSResponder
/usr/bin/killall -USR1 mDNSResponder
#syslog -w -F std.3 -k Sender discoveryd > $LOGDIR/discoveryd_$IPv6.txt &
#/usr/sbin/discoveryutil -p mdnsbrowses > $LOGDIR/sender_mdnsbrowses.txt &
#/usr/sbin/discoveryutil -p mdnsregistrations > $LOGDIR/receiver_mdnsregistrations.txt &
/usr/bin/dns-sd -V >> $LOGDIR/device_info.txt &
/sbin/ifconfig >> $LOGDIR/device_info.txt &
/usr/bin/sw_vers >> /var/root/atv_info.txt &

# Gather info about the infra AP
#/usr/local/bin/apple80211 -ssid -bssid -channel >> $LOGDIR/device_info.txt &
/usr/local/bin/wl assoc >> $LOGDIR/device_info.txt &


########################################
# AirPlay
########################################
# Enable AirPlay Service over AWDL - we better disable it as a default
#dns-sd -includeAWDL -B _airplay._tcp >> $LOGDIR/AirPlay_dns_info.txt &

# Log the AirPlay 
/usr/local/bin/airplayutil logging ".*:output=file;path=/dev/null"
sleep 1
/usr/local/bin/airplayutil logging ".*:output2=file;path=/tmp/AirPlay.log"
sleep 1
tcpdump -C 50 -W 3 -npi $interface -w $LOGDIR/tcpdump_$interface.pcap

#Lets start clean up
killall -9 apple80211
killall -9 tcpdump
killall -9 syslog
#/usr/sbin/discoveryutil -p loglevel Basic 
#netdiagnose stop ; sleep 15
cp -r /var/mobile/Library/Logs/com.apple.sharingd $LOGDIR
cp -r /var/mobile/Library/Logs/Bluetooth $LOGDIR 
cp -r /var/mobile/Library/Logs/wireless* $LOGDIR
cp -r /Library/Logs/CrashReporter $LOGDIR
cp -r /var/mobile/Library/Logs/CrashReporter/* $LOGDIR/CrashReporter2
mv /tmp/AirPlay.log $LOGDIR
#cp -r /var/log/system.log $LOGDIR
#cp -r ~/Library/Logs/com.apple.sharingd $LOGDIR
if [ ! -z $IPv6 ];then
    apple80211 awdl0 -dbg=print_sr > $LOGDIR/Services.txt &
    apple80211 awdl0 -ctl=airplaySinkSoloModeEnabled >> $LOGDIR/device_info.txt &
fi

mv $LOGDIR "${LOGDIR}.${DATE}"

tar -czvf ${LOGDIR}.${DATE}.tar ${LOGDIR}.${DATE}

echo "Uncompressed Logs saved to ${LOGDIR}.${DATE}"
echo "Compressed ${LOGDIR}.${DATE} log saved to ${LOGDIR}.${DATE}.tar"
killall sh