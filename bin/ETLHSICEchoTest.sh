delay=$1
interval=$2
iterations=$3
payload=$4

echo "Will use delay $delay, interval $interval, iterations $iterations, payload '$payload'"

qmi_interfaces="3 5 7 9 11"
event_id=487

#=========================================================

# First unload CommCenter
launchctl unload /System/Library/LaunchDaemons/com.apple.CommCenter.plist

# Now boot up the baseband
echo Powercycling Baseband
bbctl powercycle
BBUpdaterSupreme bu

# Run the drain tool on the relevant interfaces
killall USBDrain
for i in $qmi_interfaces
do
	echo "Opening drain on $i"
	USBDrain $i & >> /tmp/drain.txt
done

ETLTool USB ping

echo "Enabling events"
ETLTool nopoweron USB set-event-enabled on

echo "Enabling Event $event_id"
ETLTool nopoweron USB set-event-mask clear $event_id 

echo "Performing Test"
ETLTool nopoweron HSIC 100 hsic-echo $delay $interval $iterations $payload

echo "Listening now"
ETLTool nopoweron HSIC 100 log-listen
