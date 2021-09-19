#!/bin/sh

#  abm-sleep.sh
#  AppleBasebandManager
#
#  Created by Jesus Gutierrez on 1/7/15.
#

set -e

SLEEP_IN=$1
SLEEP_TIME=$2;
SLEEP_MAX=60

if [ -z $SLEEP_IN ]; then
	SLEEP_IN=$RANDOM
fi

if [ -z $SLEEP_TIME ]; then
	SLEEP_TIME=$RANDOM
fi

let "SLEEP_IN %= $SLEEP_MAX"
let "SLEEP_TIME %= $SLEEP_MAX"

echo "Waiting $SLEEP_IN sec, before requesting sleep";

sleep $SLEEP_IN;

abmtool power simulate 270; #kIOMessageCanSystemSleep
abmtool power simulate 280; #kIOMessageSystemWillSleep

echo "Sleep requested, waiting $SLEEP_TIME sec, before wake up";

sleep $SLEEP_TIME;

abmtool power simulate 320; #kIOMessageSystemWillPowerOn
abmtool power simulate 300; #kIOMessageSystemHasPoweredOn
