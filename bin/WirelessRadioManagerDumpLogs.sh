#!/bin/sh

LOGFILEDIR="/var/mobile/Library/Logs"
LOGFILE="WirelessRadioManager*.log"

if ls $LOGFILEDIR/$LOGFILE &> /dev/null; then

    DATE="[$(date +'%Y-%m-%d')]"
    DUMPFILEDIR="/var/mobile/Library/Logs/CrashReporter"
    
    if [ -f /usr/bin/sw_vers ] && [ -f /bin/cp ] && [ -f /usr/bin/du ] && [ -f /usr/bin/tail ] && [ -f /usr/bin/cut ]
    then
        SWVER="[$(sw_vers | grep BuildVersion | awk '{print $2}')]"
        DUMPLOGFILE="$DATE$SWVER~WirelessRadioManagerDebugInfo.tar.gz"
        SAVELOGFILE="[$(date +'%Y-%m-%d^%H:%M:%S')]$SWVER~WirelessRadioManagerDebugInfo.tar.gz"
        
        MAXLOGFILESIZE=100000
        LOGFILESIZE=$(du -k $LOGFILEDIR/$LOGFILE | sort -n | tail -1 | cut -f 1)
        
        if [ $LOGFILESIZE -ge $MAXLOGFILESIZE ]; then
            mv $LOGFILEDIR/$LOGFILE $DUMPFILEDIR &> /dev/null
            cd $DUMPFILEDIR
            tar czf $DUMPLOGFILE ./$LOGFILE &> /dev/null
            mv $DUMPLOGFILE $SAVELOGFILE &> /dev/null
        else
            cp $LOGFILEDIR/$LOGFILE $DUMPFILEDIR
            cd $DUMPFILEDIR
            tar czf $DUMPLOGFILE ./$LOGFILE &> /dev/null
        fi
        
        rm -f ./$LOGFILE
    else
        SWVER="[CS]"
        DUMPLOGFILE="$DATE$SWVER~WirelessRadioManagerDebugInfo.tar.gz"
        SAVELOGFILE="[$(date +'%Y-%m-%d^%H:%M:%S')]$SWVER~WirelessRadioManagerDebugInfo.tar.gz"
        
        MAXLOGFILESIZE=100000000
        LOGFILESIZE=$(ls -l $LOGFILEDIR/$LOGFILE | awk '{print $5}')
        
        cd $DUMPFILEDIR
        cd ..
        if [ $LOGFILESIZE -ge $MAXLOGFILESIZE ]; then
            tar czf ./CrashReporter/$SAVELOGFILE ./$LOGFILE &> /dev/null
            rm -f ./$LOGFILE &> /dev/null
        else
            tar czf ./CrashReporter/$DUMPLOGFILE ./$LOGFILE &> /dev/null
        fi
    
    fi

fi

