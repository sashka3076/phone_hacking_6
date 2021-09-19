#!/bin/sh

#  abm-reset.sh
#  AppleBasebandManager
#
#  Created by Jesus Gutierrez on 1/10/15.
#

RESET_TYPE=$1
RESET_AP_DELAY=$2
RESET_BB_DELAY=$3

DELAY_AP_MAX=300
DELAY_BB_MAX=60
TYPE_MAX=8

if [ -z $RESET_TYPE ]; then
	RESET_TYPE=$RANDOM
fi

if [ -z $RESET_AP_DELAY ]; then
	RESET_AP_DELAY=$RANDOM
fi

if [ -z $RESET_BB_DELAY ]; then
	RESET_BB_DELAY=$RANDOM
fi

let "RESET_TYPE %= $TYPE_MAX"
let "RESET_AP_DELAY %= $DELAY_AP_MAX"
let "RESET_BB_DELAY %= $DELAY_BB_MAX"

echo "Waiting $RESET_AP_DELAY sec, before triggering BB reset of type $RESET_TYPE";

sleep $RESET_AP_DELAY;

if [ $RESET_TYPE -eq 0 ]; then
	echo "Triggering an ATCS_TIMEOUT"
	ETLTool norfssync QMI raw -t 1000 WDS withHeader 01 14 00 00 01 06 00 D7 01 25 00 08 00 A1 01 00 00 A2 01 00 00
elif [ $RESET_TYPE -eq 1 ]; then
	echo "Triggering Baseband assert with GPIO"
	TelephonyBasebandTool coredump on; TelephonyBasebandTool coredump off
elif [ $RESET_TYPE -eq 2 ]; then
	echo "Triggering Baseband assert on Q6"
	ETLTool norfssync nosetup raw 4B 25 03 00 00 00 41 42 4D 20 52 45 53 45 54 00
elif [ $RESET_TYPE -eq 3 ]; then
	echo "Triggering Baseband assert on SPARROW"
	ETLTool norfssync nosetup raw 4B 25 03 10 00 00 41 42 4D 20 52 45 53 45 54 00
elif [ $RESET_TYPE -eq 4 ]; then
	echo "Triggering Baseband reset via ABM ( hard )"
	abmtool modem reset hard
elif [ $RESET_TYPE -eq 5 ]; then
	echo "Triggering Baseband reset via ABM ( soft )"
	abmtool modem reset soft
elif [ $RESET_TYPE -eq 6 ]; then
	echo "Triggerind Baseband assert with $RESET_BB_DELAY sec delay"
	printf -v RESET_BB_DELAY "%0x" $RESET_BB_DELAY
	ETLTool norfssync nosetup raw 4B 25 03 00 00 "$RESET_BB_DELAY"
else
	echo "Triggering hard reset"
	bbctl reset
fi
