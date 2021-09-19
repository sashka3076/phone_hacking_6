#!/bin/sh
#########################################################
#  AWDSetup 	                                        #
#  				                                        #
# This tool is helpful to setup AWD according the       # 
# testing conditions,environrment, purpose and platform #
#                                                       #
#  Created by Akhil Goyal                 				#
#                                                       #
#  Copyright (c) 2015 Apple. All rights reserved        #
#########################################################

NOW=$(date +"%m-%d-%Y-%H-%M-%S")
    
Usage()
{
echo "===== USAGE ======"
echo "This tool is helpful to setup AWD according the testing conditions, environrment, purpose and platform."
echo "	"
echo "Usage Help:	-h/H : --help	 	:	Print Help Menu"
echo "	"
echo "	"
echo "	====AWDSetup Usage Options - Common to all Platform:===="
echo "		-s : --state		:	Check Current AWD State (AWDVersion/AWDEnabled/DeviceID/InvestigationID/CRKey/)"
echo "	"
echo "		-r : --reset		:	Reset AWD Configuration to Factory Settings"
echo "	"
echo "		-t : --task		:	Task device with AWD Custom Configuration and Investigation ID:"
echo "							[ -d <path of custom config> -id <Investigation ID as signed int>]"
echo "						Task AWD with Hotship and Custom Investigation ID:"
echo "							[ -hotship -id <Investigation ID as signed int>]"
echo "	"
echo "		-b : --blank		:	Task AWD with Blank/Empty Configuration (Stop Collecting Any Metrics)"
echo "	"
echo "		-p : --parse-config	:	To Display Content of Current AWD Tasked Configuration:"
echo "							[ -tasked ]"
echo "						To Display Content of Any AWD Configuration:"
echo "							[ -d <path of custom awd config>]"
# echo "							To check if metric can be collected with AWD Configuration:"
# echo "								[ -metric <metric name> ] OR ---> Do not use as this option is not implemented yet."
# echo "								[ -metric <metric protoID in hex>] To get protoID refer https://awd.apple.com/metricpedia/home/index#/home  "
# echo "								Example AWDSetup -parse-config [-tasked] OR [ -d <path of custom awd config>]  [ -metric <metric name> ] OR [ -metric <metric protoID in hex>]"
echo "	"
echo "		-d : --display		:	Diaplay all AWD metriclogs in Staging Directory:"
echo "							[ -staged ]"
echo "						Display AWD metriclogs:"
echo "							[ -d <path of <metriclog>]"
echo "	"
echo "		-f : --find		:	To check if metric is collected (checks all the metriclogs on device):"
echo "							[ -mL:--metric-log <name of metric> -d <path of dir> ]"
echo "								(On iOS devices dont provide the path of dir in case you need to check all the metriclogs that exixts on device)"
echo "								(Always provide path on Mac Devices)"
echo "						To check if metric can be collected with AWD Configuration:"
echo "							[ -mC:--metric-config <metric protoid in int> -d <path of config> ]"
echo "								(dont provide the path of config in case you need to check in tasked config)"
echo "						To print all the metriclogs on device"
echo "							[ -mP:--show-metriclog -d <path of dir>]"
echo "						To dump all the metriclogs on device for sync"
echo "							[ -mD:--metriclog-dump]"
echo "	"
echo "	====AWDSetup Usage Options - Specific to iOS devices:===="
echo "		-u : --upload		:	Force upload metriclogs"
echo "							[ -ssid <name of Wifi AP> -pass <WiFi Password> (Example: AWDSetup.sh -u -ssid AppleWiFi) ]"
echo "							[ -cellular (This option should be used only if there is no WiFi available)]"
echo "	"
echo "		-tt : --timertrigger	:	Force timer trigger"
echo "							[  <timer trigger> (Example: AWDSetup.sh -tt 1m/5m/10m/15m/30m/1h/2h/4h/6h/8h/12/h/19.5h/24h) m=min/h=hour]"
echo "	"
echo "	====AWDSetup Usage Options - Specific to Mac devices:===="
echo "		-uM : --uploadMac	:	Force upload metriclogs"
echo "							[ -ssid <name of Wifi AP> -pass <WiFi Password> (Example: AWDSetup.sh -uM -ssid AppleWiFi) ]"
echo "	"
echo "		-ed : --enableDiag	:	Enable Logging for SubmitDiagnosis"
echo "	"
echo "		-fc : --forceConsolidate:	Enable force consolidate of metriclogs and copy them to /var/db/awdd/metriclogs"
# echo "		-mT : --mtask		:	Task AWD with Mobile Configuration"
# echo "							[ -mobileconfig <path of mobileconfig>]"
# echo "		-mL : --mlist		:	List the name of tasked AWD Mobile Configuration"
# echo "		-mD : --mdelete		:	Remove/Untask AWD Mobile Configuration"
# echo "							[ -mobileconfig <name of mobileconfig> use -list to display the name of mobileconfig]"
# echo "	"
# echo "		-u : --upload		:	 Force Consolidate Staging Metriclogs and Uplaod them to AWD Server"
echo "	"
echo "Version 1.5"
echo "For any issue please file radar against - Purple AWD"
echo "Owner - Akhil Goyal"
exit 1
}

stagingDir='/var/wireless/awdd/staging/'
retiredDir='/var/mobile/Library/Logs/CrashReporter/Retired/'
iteration=0

AWDState()
{
echo "Printing AWD Current Configuration State"
AWDConfigurer --info
}

IsAWDRunning()
{
result=($(cuutil proc | awk '/awdd/ {print $4}'))
if ("$result" -eq "dirty"); then
	return 1
else
	return 0
fi		
}

IsAWDExit()
{
if ( IsAWDRunning ); then
	return 0
else
	return 1
fi
}

WaitTillAWDEixt()
{

t1=($(date +"%s"))
t2=($(date +"%s"))
t3=0
while [[ (IsAWDRunning) && ("$t3" -lt 50) ]]
do
	echo "AWD is still running. Waiting for 1 sec"
	sleep 1
	t2=($(date +"%s"))
	t3=$(($t2-$t1))
done

if 	( IsAWDRunning ) ; then
	echo "AWD does not exit"
	exit 1
else
	echo "AWD exits successfully"
fi
}


WaitTillAWDAwakes()
{
t1=($(date +"%s"))
t2=($(date +"%s"))
t3=0

while [[ (IsAWDExit) && ("$t3" -lt 50) ]]
do
	sleep 1
	echo "AWD is not running. Waiting for 1 sec"
	t2=($(date +"%s"))
	t3=$(($t2-$t1))
done

if 	(IsAWDRunning) ; then
	echo "AWD awakes successfully"
else
	echo "AWD does not awake"
	exit 1
fi
}

Forceupload_iOS()
{
totalmetriclogs=0
retiredmetriclogs=0
notretiredmetriclogs=0
echo "Pushing metriclogs to AWD Server"
AWDTestingClient -ux
echo "Waiting for 5 sec"
sleep 5
files=($(find / -name '*.metriclog*' | awk -F "/" '{print $NF}'))
totalmetriclogs=($(find / -name '*.metriclog*' | wc -l ))
printf "Total MetricLogs: ---> %s\n" $totalmetriclogs
for item in ${files[*]}
do
	if [[ -f "$retiredDir/$item" ]]; then
		retiredmetriclogs=$((retiredmetriclogs+1))
		printf "MetricLog Successfully Retired : ---> %s\n" $item
	else
		notretiredmetriclogs=$((notretiredmetriclogs+1))
		printf "MetricLog Not Retired : ---> %s\n" $item
	fi	
done

metriclogsfails=$((totalmetriclogs-notretiredmetriclogs))
if [[ "$retiredmetriclogs" = "$totalmetriclogs" ]]; then
	echo "All $retiredmetriclogs metriclogs uploaded successfully"
else 
	printf "Number of MetricLogs not uploaded : ---> %s\n" $notretiredmetriclogs
	echo "Trying to upload again"
	echo "Calling OTATaskingTestClient submit for Force Upload"
	OTATaskingTestClient submit
	iteration=$((iteration+1))
	if [[ $iteration -le 10 ]]; then
		Forceupload_iOS
	else
		echo "Tried 10 times to force upload metric logs. Check if device has data (Cellular/Wifi). Exiting Now"
		exit	
	fi	
fi
}

option="${1}"
option2="$2"
option3="$3"
case ${option} in 
	-s|--state)  
		echo "AWD Current Configuration State"
		AWDConfigurer --info
		;; 
	-r|--reset)  
		echo "Reseting AWD Tasked Configuration to Defaults"
		AWDConfigurer --default
		AWDState
		;;
	-c|--task) 
		case ${option2} in 
			 -d)
			 	if [[ -z $3 ]]; then
			 		Usage
			 	else
			 		if [[ -z $4 || -z $5 ]]; then
			 			echo "Tasking AWD with Custom Configuration and Investigation ID 0"
			 			AWDConfigurer $3 0
						AWDState
			 		else
			 			echo "Tasking AWD with Custom Configuration and Investigation ID $5" 
			 			AWDConfigurer $3 $5
						AWDState
			 		fi
			 	fi
				;;
			 -hotship)
			 	if [[ -z $3 ]]; then
			 		echo "Tasking AWD with Custom Configuration and Investigation ID 0"
			 		if [[ -f  "/AppleInternal/Library/awdd/configs/hotship-internal.config" ]]; then
			 			AWDConfigurer /AppleInternal/Library/awdd/configs/hotship-internal.config 0
						AWDState
			 		else
			 			AWDConfigurer /System/Library/PrivateFrameworks/WirelessDiagnostics.framework/Support/hotship.config 0
			 			AWDState
			 		fi		
			 	else
			 		echo "Tasking AWD with Custom Configuration and Investigation ID $4"
			 		if [[ -f  "/AppleInternal/Library/awdd/configs/hotship-internal.config" ]]; then
			 			AWDConfigurer /AppleInternal/Library/awdd/configs/hotship-internal.config $4
			 			AWDState
			 		else
			 			AWDConfigurer /System/Library/PrivateFrameworks/WirelessDiagnostics.framework/Support/hotship.config $4
			 			AWDState
			 		fi
			 	fi
				;;
			*)  
      			Usage
      			exit 1 # Command to come out of the program with status 1
      			;;
		esac;;
	-b|--blank)
		echo "Tasking AWD with Blank Config"
		AWDTestingClient --rx
		AWDState
		;;
	-d|--display)
		case ${option2} in 
			-staged|-sT)
			 	echo "Printing content of all metriclogs in staging dir - /var/wireless/awdd/staging/ -- (on iOS) OR /var/db/awdd/staging/ -- (Mac)"
			 	AWDDisplay --staged --json
				;;
			-d)
			 	if [[ -z $3 ]]; then
			 		Usage
			 	else
			 		echo "Printing content of metriclog selected - $3"
			 		AWDDisplay $3 --json	
				fi
				;;
			*)  
      			Usage
      			exit 1 # Command to come out of the program with status 1
      			;;
		esac;;
	-p|--parse-config)
		case ${option2} in 
			-tasked)
				echo "This works only on Monarch/Gala or after"
			 	echo "Printing content of current tasked configuration"
			 	AWDDisplay --show-current-config --json
# 				if [[ -z $3 ]]; then
# 			 		AWDDisplay --show-current-config --json
# 			 	else
# 			 		echo "Printing content of metriclog selected - $3"
# 			 		GrepMetricinTasked()	
# 				fi
				;;
			-d)
			 	if [[ -z $3 ]]; then
			 		Usage
			 	else
			 		echo "Printing content of selected AWD configuration"
			 		AWDDisplay -c $3
				fi
				;;
			*)  
      			Usage
      			exit 1 # Command to come out of the program with status 1
      			;;
		esac;;
	-f|--find)
		case ${option2} in 
			-mL|--metric-logs)
				if [[ -z $3 ]]; then
			 		Usage
			 	else
			 		if [[ -z $4 || -z $5 ]]; then
			 			echo "Checking in metriclogs in dir / if metric <$3> is collected"
						files=($(find / -name "*.metriclog*"))
						for item in ${files[*]}
						do
 							printf "MetricLog: ---> %s\n" $item
 							AWDDisplay $item | grep -i -n4 --color $3
						done
					else
						echo "Checking in metriclogs in dir $5 if metric <$3> is collected"
						files=($(find $5 -name "*.metriclog*"))
						for item in ${files[*]}
						do
 							printf "MetricLog: ---> %s\n" $item
 							AWDDisplay $item | grep -i -n4 --color $3
						done
					fi	
				fi
				;;
			-mC|--metric-config)
				if [[ -z $3 ]]; then
			 		Usage
			 	else
			 		if [[ -z $4 && -z $5 ]]; then
			 			echo "This works only on Monarch/Gala or after"
			 			echo "Checking if metric is collected by tasked config"
			 			AWDDisplay --show-current-config --json | grep -i --color -n2 $3
			 		else
			 			echo "Checking if metric is collected by $5 config"
			 			AWDDisplay -c $5 | grep -i --color -n2 $3
			 		fi
			 	fi
				;;
			-mP|--show-metriclog)
				if [[ -z $3 || -z $4 ]]; then
					echo "Checking metriclogs in dir / "
					files=($(find / -name "*.metriclog*"))
					for item in ${files[*]}
					do
						printf "MetricLog: ---> %s\n" $item
					done
				else
					echo "Checking metriclogs in dir $4"
					files=($(find $4 -name "*.metriclog*"))
					for item in ${files[*]}
					do
						printf "MetricLog: ---> %s\n" $item
					done
				fi	
				;;
			-mD|--metriclog-dump)
				if [[ -z $3 ]]; then
			 		Usage
			 	else
			 		mkdir /var/wireless/Library/Logs/CrashReporter/$(date +"%F-%T")_awdd_metriclogs && find / -name '*.metriclog' -exec ditto {} "$_/{}.log" \;
				fi
				;;
			*)  
      			Usage
      			exit 1 # Command to come out of the program with status 1
      			;;
		esac;;
	-u|--upload)
			case ${option2} in 
			-ssid)
			 	if [[ -z $3 ]]; then
			 		Usage
			 	else [[ -n $3 ]]
					echo "Starting to force upload metriclogs"
					echo "Enabling Wifi"
					mobilewifitool -- manager power 1
					echo "Waiting for 5 sec"
					sleep 5
					echo "checking if Wifi associated with any AP"
					result=($(wl ssid | awk -F\" '{print $(NF-1)}'))
					if [[ -z $result ]]; then
						echo "Cannot find any Auto Join Wifi Network"
						echo "Trying to connect with $3 WiFi AP"
						mobilewifitool -- join -i en0 --ssid=$3 --password=$5 --apmode=any
						echo "Waiting for 5 sec"
						sleep 5
						wifiap=($(wl ssid | awk -F\" '{print $(NF-1)}'))
						if [[ "$wifiap" = "$3" ]]; then
							echo "Successfully joined $3 WifiAP"
							echo "Trying to upload metriclogs on Wifi"
							Forceupload_iOS
						else
							echo "Failed to join $3 WifiAP"
							echo "Join to Wifi AP to make sure metriclogs upload successfully"
							echo "Trying to check if AppleWiFI is available"
							applewifi=($(wifitool -s | grep AppleWiFi | awk -F\" '{print $(NF-1)}'))
							if [[ -n "$applewifi" ]]; then
								"AppleWiFi seems to be available"
								"Trying to join AppleWiFi"
								mobilewifitool -- join -i en0 --ssid=AppleWiFi
								output=($(wl ssid | awk -F\" '{print $(NF-1)}'))
								if [[ "$output" -eq "AppleWiFi" ]]; then
									echo "Successfully joined AppleWiFi"
									echo "Trying to upload metriclogs on Wifi"
									Forceupload_iOS
								else
									echo "Failed to join Apple WiFi"
									echo "Join to Wifi AP to make sure metriclogs upload successfully"
									echo "Now trying to upload metriclogs on cellular"
									Forceupload_iOS
								fi
							fi
						fi
					else
						echo "Connected to Wifi AP Successfully"
						echo "Trying to upload metriclogs on Wifi"
						Forceupload_iOS
					fi	
				fi
				;;
			-cellular)
      			echo "Warning - You are trying to upload metriclogs over Cellular"
      			echo "If WiFis available use run this command as:"
      			echo ""
				echo "Now trying to upload metriclogs on cellular"
				Forceupload_iOS
				;;
			*) 
      			Usage
      			exit 1 # Command to come out of the program with status 1
      			;;						
		esac;;
	-tt|--timertrigger)
			echo "Firing timer trigger $2"
			case ${option2} in
					1m)
					WaitTillAWDAwakes
					AWDTestingClient -c 12 -t 520199 -x
					WaitTillAWDEixt
					;;
					5m)
					WaitTillAWDAwakes
					AWDTestingClient -c 12 -t 520207 -x
					WaitTillAWDEixt
					;;
					10m)
					WaitTillAWDAwakes
					AWDTestingClient -c 12 -t 520200 -x
					WaitTillAWDEixt
					;;
					15m)
					WaitTillAWDAwakes
					AWDTestingClient -c 12 -t 520204 -x
					WaitTillAWDEixt
					;;
					30m)
					WaitTillAWDAwakes
					AWDTestingClient -c 12 -t 520205 -x
					WaitTillAWDEixt
					;;
					1h)
					WaitTillAWDAwakes
					AWDTestingClient -c 12 -t 520197 -x
					WaitTillAWDEixt
					;;
					2h)
					WaitTillAWDAwakes
					AWDTestingClient -c 12 -t 520206 -x
					WaitTillAWDEixt
					;;
					4h)
					WaitTillAWDAwakes
					AWDTestingClient -c 12 -t 520198 -x
					WaitTillAWDEixt
					;;
					6h)
					WaitTillAWDAwakes
					AWDTestingClient -c 12 -t 520201 -x
					WaitTillAWDEixt
					;;
					8h)
					WaitTillAWDAwakes
					AWDTestingClient -c 12 -t 520202 -x
					WaitTillAWDEixt
					;;
					12h)
					WaitTillAWDAwakes
					AWDTestingClient -c 12 -t 520203 -x
					WaitTillAWDEixt
					;;
					19.5h)
					WaitTillAWDAwakes
					AWDTestingClient -c 12 -t 520195 -x
					WaitTillAWDEixt
					;;
					24h)
					WaitTillAWDAwakes
					AWDTestingClient -c 12 -t 520196 -x
					WaitTillAWDEixt
					;;
					*)
					Usage
					;;
			esac;;
	-uM|--uploadMac)
		echo "Trying to find Active Network"
		wifiinterface=($(networksetup -listallhardwareports | grep -A1 Wi-Fi | grep Device | awk -F " " '{print $(2)}'))
		corewlan $wifiinterface setPower 1
		status=($(ifconfig | grep -i "status: active" | awk -F " " '{print $(NF)}'))
		if [[ -z $status ]]; then
			echo "Cannot find any Active Networks. Connect to Wifi or Ethernet"
			exit 1
		else	
			echo "Network is Active"
			echo "Trying to force upload metriclogs. This might take 2-3 min."
			AWDTestingClient -ux
			/System/Library/CoreServices/SubmitDiagInfo full-submission
		fi	
		;;
   	-ed|--enableDiag)  
		echo "Enabled Logging for SubmitDiagnosis"
		defaults write /Library/Application\ Support/CrashReporter/DiagnosticMessagesHistory.plist DebugLogging YES
      	;;		
   	-fc|--forceConsolidate)  
		echo "Enabled Consolidation of metriclogs"
		sudo defaults write com.apple.awdd.persistent force_consolidated -bool yes
      	;;			 		
   	-h|--help|*)  
      	Usage
      	exit 1 # Command to come out of the program with status 1
      	;; 
esac