#!/bin/bash

diversity_nv_1=818
diversity_nv_2=1018

pref_nv=10

mode_automatic="00 04"
mode_cdma_only="00 09"
mode_hdr="00 0A"

function write_nv
{
    tool="ETLTool USB nvwrite"
    item=$1
    value=$2

    echo -n "Setting NV Item $item to $value..."

    $tool $item $value
    if [ $? -eq 0 ]
    then
        echo "SUCCESS"
    else
        echo "FAILED"
        exit 1
    fi
}

function ping
{
    tool="ETLTool USB ping verify"
    result=-1
    
    echo -n "Pinging..."
    bbctl radio on 
    for (( tries = 0; tries < 4; tries++ ))
    do

        $tool > /dev/null
        if [ $? -eq 0 ]
        then
            result=$?
            echo "SUCCESS"
            break
        else
            echo "FAILED"
            bbctl reset
            bbctl radio on
            sleep 2
        fi
    done

    if [ $result -ne 0 ]
    then
        echo "Pinging failed"
        exit 1
    fi 
}

function print_usage
{
    echo "Usage:"
    echo -e "\tmode ['reset']"
    echo -e "\t- mode can be 'cdma-only', 'hdr' or 'automatic'"
    echo -e "\t- If 'reset' is specified, a baseband reset will be done after setting the mode"
    echo ""
    echo -e "Examples:"
    echo -e "\t$0 cdma-only reset"
    echo -e "\t\tThis will set the rx path to cdma-only and then reset the baseband"
    echo ""
    echo -e "\t$0 automatic"
    echo -e "\t\tThis will set the rx path to automatic, but NOT reset the baseband."
    
}

mode=$1
reset=$2

diversity_num_1=0
diversity_num_2=0

case $mode in
    cdma-only ) mode_num="$mode_cdma_only";;
    hdr ) mode_num="$mode_hdr";;
    automatic ) mode_num="$mode_automatic"; diversity_num_1=1;;
    *) echo "Unrecognized mode '$mode'"; print_usage; exit;;
esac

bbctl radio on

ping

write_nv $diversity_nv_1 $diversity_num_1
write_nv $diversity_nv_2 $diversity_num_2

write_nv $pref_nv "$mode_num"

if [ "$reset" == "reset" ]
then
    echo "Resetting baseband for options to take effect"
    echo -e "\t-You will see a BB crash detected if CommCenter is loaded" 

    ETLTool USB power-down
    if [ $? -eq 0 ]
    then
        sleep 1
        bbctl radio on 
    else
        echo "Warning: Failed to do clean power down, issuing hard reset"
        bbctl reset
    fi
    sleep 1
    ping
fi
