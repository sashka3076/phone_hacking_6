#!/bin/bash

LOGDIR=""

while getopts ":d:" opt; 
do
	case $opt in
	    d)
		 echo "Enter the logs dir path :: $OPTARG"
		 LOGDIR=$OPTARG
		 ;;
		?)
		 echo " Error:: Invalid option: -$OPTARG"
		 usage
		 exit 1
		 ;;
		:)
		 echo "Option -$OPTARG requires a path as an argument" 
		 exit 1
                 ;;
	esac

done
KILLALL=`which killall`
count=0
count=$[$count + 1]
apple80211 awdl0 -quiet -logf="vv set" -outfile=$LOGDIR/awdlFamily_$count.pcap -dlog &
sleep 90
while [ 1 ]; do
	count=$[$count + 1]
	$KILLALL apple80211
	apple80211 awdl0 -quiet -logf="vv set" -outfile=$LOGDIR/awdlFamily_$count.pcap -dlog &
    sleep 90
    filename="$LOGDIR/awdlFamily_$[$count-2].pcap"
    echo "Filename : $filename"
    if [ -f $filename ];then
        echo "Removing file : $filename";
        `rm -f $filename`;
    else
        echo "no $filename exists";
    fi
done