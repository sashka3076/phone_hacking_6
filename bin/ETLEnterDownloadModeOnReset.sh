item=4399
tool_cmd=ETLTool
arg=$1

if [ $arg == "on" ]
then
    on_off="01"
else
    if [ $arg == "off" ]
    then
        on_off="00";
    else
        echo "You must specify either 'on' or 'off'"
        exit
    fi
fi

$tool_cmd ping
if [ $? -eq 0 ]
then
    echo "Setting Enabling entering of Download Mode upon reset to $on_off"
    $tool_cmd nvwrite $item $on_off
else
    echo "Couldn't ping radio"
fi

