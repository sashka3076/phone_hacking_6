#!/bin/sh

#  collectWiFiDebugInfo.sh
#  WirelessUtilities
#
# Collect useful wifi debug information

WIFI_LOG_DIR="/var/mobile/Library/Logs/CrashReporter/WiFi"
SYSCONFIG_DIR="/Library/Preferences/SystemConfiguration"
CC_LOGDIR_1="/Library/Logs/CrashReporter/com.apple.driver.AppleBCMWLANCore"
CC_LOGDIR_2="/Library/Logs/CrashReporter/com.apple.io80211_AWDLFamily"
CC_LOGDIR_3="/Library/Logs/CrashReporter/CoreCapture"
USER_REASON_STR=

## Handle some arguments
while getopts o:r:dnh flag; do
    case $flag in
        d)
            echo "Debug enabled"
            DEBUG_SCRIPT=1
            ;;
        o)
            echo "Overriding output directory: $OPTARG"
            WIFI_LOG_DIR=$OPTARG
            ;;
        r)
            echo "Adding reason string: $OPTARG"
            USER_REASON_STR=$OPTARG
            ;;
        n)
            echo "Skipping kernel dump"
            SKIP_KERNEL_DUMPS=1
            ;;
        h)
            echo "Usage: $0 [-d] [-o /path/]"
            echo
            echo "          -o /path/     - Override the output directory"
            echo "          -d            - Debug the script"
            echo "          -n            - Skip the CC kernel dumps"
            echo "          -r            - Reason string"
            echo
            echo
            exit 0
            ;;
    esac
done


### FIXME: TTR currently uses the following regex to parse out the file name:
### NSString *regex = @"/[^ \n_]*";
### Changing the '_' to a '^' to allow this to pass
#LOG_SNAPSHOT="[$(date +'%Y-%m-%d_%H,%M,%S')]~WiFiDebugInfo"
LOG_SNAPSHOT="[$(date +'%Y-%m-%d^%H,%M,%S')]~WiFiDebugInfo"
LOG_DIR="$WIFI_LOG_DIR/$LOG_SNAPSHOT"
mkdir -p $LOG_DIR
chown mobile:mobile $WIFI_LOG_DIR
mkdir -p $LOG_DIR/WiFiManager

WAIT_COUNT=0
WAIT_PIDS=
KILL_COUNT=0
KILL_PID=

# Redirect stdout/stderr to a file we will capture. Save original stdout as fd
# 3 as stdout. fd 4 can be used for debug, for now sending to same
# 'script_debug.txt' file.
exec 3>&1
exec 1>$LOG_DIR/script_debug.txt
exec 2>&1
exec 4>&1

if [ ! -z $DEBUG_SCRIPT ] ; then
    #set -x
    exec 4>&3
fi

debug ()
{
    echo "$(date) -- $*" >&4
}

# Query interface:
INTERFACES=
for INTF in $(ifconfig | awk '/^(en|ap|awdl)[0-9]*:/ { sub(/:/,"",$1); print $1 }') ; do
    /usr/local/bin/apple80211 ${INTF} --driver >/dev/null 2>&1
    if [ $? == 0 ]; then
        INTERFACES="${INTERFACES} ${INTF}"
    fi
done

pingMMI()
{
    # Traffic Class (Specifies Device WME Queue used for DUT Tx)
    PING_TC[0]=0  # BE
    PING_TC[1]=1  # BK
    PING_TC[2]=2  # VI
    PING_TC[3]=3  # VO

    # TOS Priorities (Specifies AP WME Queue used for DUT Rx)
    PING_TOS[0]=0x00 # BE
    PING_TOS[1]=0x20 # BK
    PING_TOS[2]=0x80 # VI
    PING_TOS[3]=0xC0 # VO

    # TOS Priorities (Specifies AP WME Queue used for DUT Rx)
    PING_QUEUE[0]='BE' # BE
    PING_QUEUE[1]='BK' # BK
    PING_QUEUE[2]='VI' # VI
    PING_QUEUE[3]='VO' # VO

    PING_SWEEP_STEP=128
    PING_SWEEP_SMALL_MIN=0
    PING_SWEEP_SMALL_MAX=648
    PING_SWEEP_LARGE_MIN=776
    PING_SWEEP_LARGE_MAX=1536

    PING_INTERVAL=0.11

    PING_SLEEP=0.11

    PING_TIMEOUT=3

    local dest_ip="$1"
    local INTF=$2


    for (( i=0 ; i < ${#PING_TOS[*]} && i < ${#PING_TC[*]} ; ++i )) ; do

        # Generate a random length for the ping pattern
        local pingPatternLength=`od -N1 -An -t u1  /dev/urandom`     # Generate number [0 255]
        local pingPatternLength=$(( (pingPatternLength / 16) + 1 ))  # Redistribute to [1 16]

        # Generate random ping pattern, [1 16] random bytes
        local pingPattern=`od -N $pingPatternLength -An -t xC /dev/urandom | sed -e 's/ //g'`


        sleep $PING_SLEEP

        # Ping Command
        # -g $PING_SWEEP_MIN -h $PING_SWEEP_STEP -G $PING_SWEEP_MAX
        #   Send pings with paylods from PING_SWEEP_MIN to PING_SWEEP_MAX bytes in PING_SWEEP_STEP byte increments
        # -i PING_INTERVAL
        #   Send pings every PING_INTERVAL seconds
        # -p $pingPattern
        #   Fill the ping payload with the random pattern supplied.
        # -z $wmeQueue
        #   Use the specified ToS to send pings on the specified WME queue.
        # -t $timeout
        #   Specify a timeout, in seconds, before ping exits regardless of how many packets have been received.

        echo ''
        echo ''
        echo ''
        echo "${PING_QUEUE[$i]}: Short Packets"
        echo ''
        echo "ping -b $INTF -t $PING_TIMEOUT -g $PING_SWEEP_SMALL_MIN -h $PING_SWEEP_STEP -G $PING_SWEEP_SMALL_MAX -i $PING_INTERVAL -p $pingPattern -k ${PING_TC[$i]} -z ${PING_TOS[$i]}  $dest_ip"

        ping -b $INTF -t $PING_TIMEOUT -g $PING_SWEEP_SMALL_MIN -h $PING_SWEEP_STEP -G $PING_SWEEP_SMALL_MAX -i $PING_INTERVAL -p $pingPattern -k ${PING_TC[$i]} -z ${PING_TOS[$i]}  $dest_ip
        PING_RET=$?
        if [ $PING_RET == 77 ] ; then
            # <rdar://problem/13512721> Ping should allow fast-pings from mobile user
            echo "Fast ping not supported. Reverting to simple ping test. ($PING_RET)"
            echo ping -c 3 -t $PING_TIMEOUT $dest_ip
            ping -c 3 -t $PING_TIMEOUT $dest_ip
            break;
        fi
        if [ $PING_RET != 1 ] && [ $PING_RET != 0 ] ; then
            echo "Ping unable to transmit, giving up! ($PING_RET)"
            break;
        fi

        echo ''
        echo "${PING_QUEUE[$i]}: Long Packets"
        echo ''
        echo "ping -b $INTF -t $PING_TIMEOUT -g $PING_SWEEP_LARGE_MIN -h $PING_SWEEP_STEP -G $PING_SWEEP_LARGE_MAX -i $PING_INTERVAL -p $pingPattern -k ${PING_TC[$i]} -z ${PING_TOS[$i]}  $dest_ip"

        ping -b $INTF -t $PING_TIMEOUT -g $PING_SWEEP_LARGE_MIN -h $PING_SWEEP_STEP -G $PING_SWEEP_LARGE_MAX -i $PING_INTERVAL -p $pingPattern -k ${PING_TC[$i]} -z ${PING_TOS[$i]}  $dest_ip
        PING_RET=$?
        if [ $PING_RET != 1 ] && [ $PING_RET != 0 ] ; then
            echo "Ping unable to transmit, giving up! ($PING_RET)"
            break;
        fi

    done
}

function PingTest {
    debug "PingTest start"

    PING_COUNT=0
    PING_PID=

    # Start infra pings
    for INTF in ${INTERFACES} ; do
        case ${INTF} in
            en*)
                GATEWAY=$(/usr/sbin/netstat -f inet -nr | /usr/bin/grep default | /usr/bin/grep ${INTF} | /usr/bin/awk '{print $2}')
                echo "Gateway is: $GATEWAY" > $LOG_DIR/ping_${INTF}_gateway.txt
                if [ "x$GATEWAY" != "x" ]; then
                    pingMMI ${GATEWAY} "${INTF}" >> $LOG_DIR/ping_${INTF}_gateway.txt 2>&1 &
                    PING_PID[$PING_COUNT]=$!
                    PING_COUNT=$((PING_COUNT+1))
                fi

                pingMMI www.apple.com "$INTF" >> $LOG_DIR/ping_${INTF}_apple-com.txt 2>&1 &
                PING_PID[$PING_COUNT]=$!
                PING_COUNT=$((PING_COUNT+1))
                ;;
        esac
    done

    # Send a couple pings to each interface broadcast.
    for INTF in $(ifconfig | awk '/(ap|en|awdl|bridge)[a-z0-9]*:/ { sub(/:/,"",$1); print $1 }') ; do
        # Don't filter by our interfaces, for ap interface, we get ip from bridge interface.
        #/usr/local/bin/apple80211 ${INTF} --driver >/dev/null 2>&1
        #if [ $? == 0 ]; then
            BCAST=$(ifconfig $INTF | sed -n -e 's/.*broadcast //p')
            if [ "INTF$BCAST" != "INTF" ] ; then
                BCAST=224.0.0.1 ## just use the rfc1112 'all systems' address
                ping -b $INTF -i 0.12 -c 3 $BCAST 1>> $LOG_DIR/ping_${INTF}_${BCAST}.txt 2>&1 &
                PING_PID[$PING_COUNT]=$!
                PING_COUNT=$((PING_COUNT+1))
            fi
            ifconfig $INTF | grep -q "inet6"
            if [ $? == 0 ] ; then
                ping6 -I $INTF -B $INTF -c 3 ff02::1 -n 1>> $LOG_DIR/ping_${INTF}_v6_bcast.txt 2>&1 &
                PING_PID[$PING_COUNT]=$!
                PING_COUNT=$((PING_COUNT+1))
            fi
        #fi
    done

    debug "PingTest wait"
    for (( PING_COUNT=0 ; PING_COUNT < "${#PING_PID[@]}" ; PING_COUNT++ )); do
        if [ "x${PING_PID[$PING_COUNT]}" != "x" ] ; then
            wait ${PING_PID[$PING_COUNT]}
        fi
    done

    debug "PingTest end"
}

function TCPTest {
    for INTF in ${INTERFACES} ; do
        case ${INTF} in
            en*)
                debug "Starting http request to apple.com"
                HTTP_URL=http://www.apple.com/library/test/success.html
                /usr/local/bin/curl -m 10 -s -S -v --interface ${INTF} -D - -o - ${HTTP_URL} >${LOG_DIR}/http_test.txt 2>&1 &
                WAIT_PID[$WAIT_COUNT]=$!
                WAIT_COUNT=$((WAIT_COUNT+1))
                ;;
        esac
    done
}

##
function DoCommand {
    echo "-------------------- $1" >> $2
    (exec $1 >> $2 2>&1)
}

### Commands that we want to sample twice
function RunTwiceCommands {
    OUTFILE=$LOG_DIR/$1
    debug "Starting '$1' collection"
    echo "---------------------------------------- $(date)" >> "$OUTFILE"

    for INTF in ${INTERFACES} ; do
        case ${INTF} in
            en*)
                DoCommand "/usr/local/bin/apple80211 ${INTF} -dbg=m" "$OUTFILE"
                DoCommand "/usr/local/bin/apple80211 ${INFTF} -dbg=bgscan-private-mac" "$OUTFILE"
                DoCommand "/usr/local/bin/apple80211 ${INTF} -dbg=proptx" "$OUTFILE"
                DoCommand "/usr/local/bin/wl -i ${INTF} wme_counters" "$OUTFILE"
                DoCommand "/usr/local/bin/wl -i ${INTF} counters" "$OUTFILE"
                DoCommand "/usr/local/bin/wl -i ${INTF} memuse" "$OUTFILE"
                ;;
        esac

        echo "==================== ${INTF} ====================" >> "$OUTFILE"
        DoCommand "netstat -I ${INTF} -q" "$OUTFILE"
        DoCommand "/usr/local/bin/apple80211 ${INTF} -dbg=print_peers" "$OUTFILE"
        DoCommand "/usr/local/bin/apple80211 ${INTF} -dbg=print_packets" "$OUTFILE"
        DoCommand "/usr/local/bin/apple80211 ${INTF} -dbg=print_all_peers_verbose" "$OUTFILE"
    done

    debug "Starting syslog tail"
    echo "---------------------------------------- $(date)" >> $LOG_DIR/syslog.txt
    syslog >> $LOG_DIR/syslog.txt

    (cd $LOG_DIR && /usr/local/bin/crstackshot)
}

### Commands that we want to sample once
function RunOnceCommands {
    OUTFILE=$LOG_DIR/$1
    debug "Starting '$1' collection"
    echo "---------------------------------------- $(date)" >> "$OUTFILE"
    DoCommand "sw_vers" "$OUTFILE"
    DoCommand ifconfig "$OUTFILE"
    DoCommand "netstat -nr" "$OUTFILE"
    for INTF in ${INTERFACES} ; do
        echo "==================== ${INTF} ====================" >> "$OUTFILE"
        DoCommand "/usr/local/bin/wl -i ${INTF} cur_etheraddr" "$OUTFILE"
        DoCommand "/usr/local/bin/apple80211 ${INTF} -power" "$OUTFILE"
        case ${INTF} in
            awdl*)
                DoCommand "/usr/local/bin/apple80211 ${INTF} -awdl" "$OUTFILE"
                DoCommand "/usr/local/bin/apple80211 ${INTF} -dbg=print_sr" "$OUTFILE"
                #DoCommand "/usr/local/bin/apple80211 ${INTF} --dbg=a-peer-cache" "$OUTFILE"  ##DISABLED: Causes command failure if AWDL is disabled
                DoCommand "/usr/local/bin/apple80211 ${INTF} --verbose=1 -dbg=print_awdl_peers" "$OUTFILE"
                #DoCommand "/usr/local/bin/apple80211 ${INTF} --dbg=a-peers" "$OUTFILE  ##DISABLED: Causes command failure if AWDL is disabled"
                ;;
            ap*)
                DoCommand "/usr/local/bin/wl -i ${INTF} assoclist" "$OUTFILE"
                ;;
            en*)
                DoCommand "/usr/local/bin/apple80211 ${INTF} --driver" "$OUTFILE"
                DoCommand "/usr/local/bin/wl -i ${INTF} ver" "$OUTFILE"
                DoCommand "/usr/local/bin/wl -i ${INTF} status" "$OUTFILE"
                DoCommand "/usr/local/bin/apple80211 ${INTF} --dbg=scan-cache" "$OUTFILE"
                DoCommand "/usr/local/bin/wl -i ${INTF} ccode_info" "$OUTFILE"
                ;;
        esac
    done
    DoCommand "/usr/local/bin/memdump -r -a syscfg" "$OUTFILE"
    DoCommand "/usr/sbin/netstat -mmm" "$OUTFILE"
    DoCommand "/usr/local/bin/mobilewifitool manager clients" "$OUTFILE"
    DoCommand "/bin/ps alxw" "$OUTFILE"
    DoCommand "/usr/local/bin/profilectl list" "$OUTFILE"
    #echo "show .* p" | scutil > $LOG_DIR/dynamic_store.txt
    #TODO: deviceInfo.txt
}

################################################################################

debug "INTERFACES ARE: ${INTERFACES}"

# By popular request, dump data path prior to ping test too.
if [ -z $SKIP_KERNEL_DUMPS ] ; then
    for INTF in $INTERFACES; do
        case ${INTF} in
            en*)
                debug "Starting captureDataPathInfo"
                /usr/local/bin/apple80211 ${INTF} --dbg="captureDataPathInfo -block ${USER_REASON_STR:+-msg=}${USER_REASON_STR}"
                ;;
        esac
    done
fi

debug "Starting sample of sharingd"
cp -r /var/mobile/Library/Logs/com.apple.sharingd $LOG_DIR/ &

debug "Starting sample of Bluetooth"
cp -r /var/mobile/Library/Logs/Bluetooth/BTServer-latest.log $LOG_DIR/ &
cp -r /var/mobile/Library/Logs/wirelessproxd-latest.log $LOG_DIR/ &

debug "Starting sample of wifid"
/usr/bin/sample wifid 5 5 -mayDie -file $LOG_DIR/WiFiManager/wifid_sample.txt &
WAIT_PID[$WAIT_COUNT]=$!
WAIT_COUNT=$((WAIT_COUNT+1))

#
debug "Starting get-mobility-info"
/usr/local/bin/get-mobility-info > /tmp/$$_get-mobility-info.txt &
WAIT_PID[$WAIT_COUNT]=$!
WAIT_COUNT=$((WAIT_COUNT+1))

# First pass at collecting info
RunTwiceCommands dump_001.txt

ioreg -w0 -x -l > $LOG_DIR/ioreg.txt &
WAIT_PID[$WAIT_COUNT]=$!
WAIT_COUNT=$((WAIT_COUNT+1))

/usr/local/bin/iordump > $LOG_DIR/iordump.txt &
WAIT_PID[$WAIT_COUNT]=$!
WAIT_COUNT=$((WAIT_COUNT+1))

/usr/local/bin/wifistats -vfri 30 > $LOG_DIR/wifistats.txt &
KILL_PID[$KILL_COUNT]=$!
KILL_COUNT=$((KILL_COUNT+1))

for INTF in $INTERFACES; do
    case ${INTF} in
        en*)
            echo "traceroute -i ${INTF} -e -P UDP -q 1 -w 1 -m 15 -n www.apple.com" > $LOG_DIR/traceroute_${INTF}_apple-com.txt
            traceroute -i ${INTF} -e -P UDP -q 1 -w 1 -m 15 -n www.apple.com >> $LOG_DIR/traceroute_${INTF}_apple-com.txt 2>&1 &
            KILL_PID[$KILL_COUNT]=$!
            KILL_COUNT=$((KILL_COUNT+1))
            ;;
    esac

done

TCPTest
PingTest

RunOnceCommands system_state.txt

if [ -z $SKIP_KERNEL_DUMPS ] ; then
    for INTF in $INTERFACES; do
        case ${INTF} in
            en*)
                debug "Starting captureDebugInfo "
                /usr/local/bin/apple80211 ${INTF} --dbg="captureDebugInfo -block ${USER_REASON_STR:+-msg=}${USER_REASON_STR}"
                ;;
        esac
    done

    # 'captureDebugInfo -block' is only synchronous to taking the actual SOC
    # reads and signaling CoreCapture. Short sleep used to allow corecaptured
    # the chance to run before collecting the logs.
    debug "Sleeping 4 seconds for CC to run"
    sleep 4  # Sleep 2 was not enough to catch CC files, increasing to 4
fi

debug "Starting copy of SYSCONFIG_DIR"
cp -r $SYSCONFIG_DIR $LOG_DIR/

# Grab Family legacy bpf logging
if [ -e /tmp/pcapdump.cap ] ; then
    debug "Copy /tmp/pcapdump.cap"
    cp /tmp/pcapdump.cap $LOG_DIR/
fi

# WiFi Manager: Dump wifid log buffer and copy all dumped logs
debug "Dump wifid log buffer and copy all dumped logs"
mobilewifitool -- log --dumpLogBuffer
cp /var/mobile/Library/Logs/CrashReporter/WiFi/WiFiManager/*.log $LOG_DIR/WiFiManager/

# WiFi Manager: Grab the last 10k lines from /Library/Logs/wifi.log
if [ -e /Library/Logs/wifi.log ] ; then
    debug "Starting wifi.log tail"
    tail -n 10000 /Library/Logs/wifi.log >> $LOG_DIR/WiFiManager/wifi.log
fi

# WiFi Manager: Grab wifid logs that might have been collected to crashreporter due to wifi logging profile
debug "Starting copy of wifid logging profile logs"
cp /var/mobile/Library/Logs/CrashReporter/WiFi/*.log $LOG_DIR/WiFiManager/


# Second pass at collecting info
RunTwiceCommands dump_002.txt

# iCloud syncing debug info
debug "Starting iCloud Sync log copy"
/usr/local/bin/security sync -i &> $LOG_DIR/keychainCircleStatus.txt
/usr/local/bin/security item -q class=genp,sync=1,svce=AirPort > $LOG_DIR/syncableKeychainItems.txt
/usr/local/bin/security item -q class=genp,sync=0,svce=AirPort > $LOG_DIR/NonSyncableKeychainItems.txt
cp /var/mobile/Library/SyncedPreferences/com.apple.wifid.plist $LOG_DIR/kvs.plist

debug "Grabbing com.apple.networking.*"
mkdir -p $LOG_DIR/com.apple.networking/
find /Library/Logs/CrashReporter/ -name "com.apple.networking.*" -mindepth 1 -maxdepth 1 -ctime -60m -exec cp "{}" "$LOG_DIR/com.apple.networking/" \;

# Grab the last 10k lines from logs:
debug "Starting corecaptured.log tail"
tail -n 10000 /var/{logs,log}/corecaptured.log >> $LOG_DIR/corecaptured.log

debug "Starting cp of logdumperd log"
cp /var/logs/com.apple.wifi.logdumperd.log $LOG_DIR/

# Wait for the async stuff to complete ...
for (( count=0 ; count < "${#WAIT_PID[@]}" ; count++ )); do
    if [ "x${WAIT_PID[$count]}" != "x" ] ; then
        debug "WAIT ${WAIT_PID[$count]}"
        wait ${WAIT_PID[$count]}
    fi
done

# send kill to processes in kill list and wait for exit
for (( count=0 ; count < "${#KILL_PID[@]}" ; count++ )); do
    if [ "x${KILL_PID[$count]}" != "x" ] ; then
        debug "Kill ${KILL_PID[$count]}"
        kill -15 ${KILL_PID[$count]}
        wait ${KILL_PID[$count]}
    fi
done

# Copy recent captured logs
# Only consider captures from the last 30 min. Only keep most recent 4.
for CC_LOGDIR in $(ls -d $CC_LOGDIR_1*); do
    if [ -d $CC_LOGDIR ] ; then
        find ${CC_LOGDIR}/ -mindepth 1 -maxdepth 1 -ctime -30m | sort | tail -n 4 >> /tmp/$$_cc_list.txt
        find ${CC_LOGDIR}/ >> $LOG_DIR/cc_file_list.txt
    fi
done

if [ -d $CC_LOGDIR_2 ] ; then
     find ${CC_LOGDIR_2}/ -mindepth 1 -maxdepth 1 -ctime -30m | sort | tail -n 2 >> /tmp/$$_cc_list.txt
fi

if [ -d $CC_LOGDIR_3 ] ; then
     find ${CC_LOGDIR_3}/ -mindepth 2 -maxdepth 2 -ctime -30m | sort | tail -n 10 >> /tmp/$$_cc_list.txt
fi

if [ -e /tmp/$$_cc_list.txt ] ; then
    debug "Starting cc log rsync"
    cat /tmp/$$_cc_list.txt | tr '\n' '\0' | xargs -0 -I {} rsync -a "{}" $LOG_DIR/
    mv /tmp/$$_cc_list.txt $LOG_DIR/
    #rm /tmp/$$_cc_list.txt
fi

# Copy over the mobility info stuff
GMI=$(cat /tmp/$$_get-mobility-info.txt | sed -n -e 's/Network data collected to "\(.*\)"/\1/p')
if [ -e "$GMI"  ] ; then
    debug "Starting copy of get-mobility-info output"
    cp "$GMI" $LOG_DIR/
fi

debug "Starting packaging "
# Package
tar -czf "$LOG_DIR.tar.gz" -C "$WIFI_LOG_DIR" "$LOG_SNAPSHOT"

debug "Starting clean "
# Clean
rm -rf $LOG_DIR
debug "DONE"

echo "Collected Debug Info: $LOG_DIR.tar.gz" >&3


