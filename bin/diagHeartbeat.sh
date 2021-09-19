#!/bin/bash

SERVER="https://iphonesubmissions.apple.com/convert.jsp"
while [[ $# > 0 ]]
do
	key="$1"
	shift

	case $key in
		-u|--uat)
		SERVER="https://iphonesubmissions-test2.apple.com/convert.jsp"
		;;
		*)
		# unknown option
		;;
	esac
done

key=$(gestalt_query InverseDeviceID | cut -d '"' -f 2)
type=$(gestalt_query ProductType | cut -d '"' -f 2)
#os_version
echo "{\"bug_type\":\"164\",\"crashreporter_key\":\"$key\",\"machine_config\":\"$type\"}" > /tmp/sub_diag.log
submissionDiag.sh --allLogs --skipBTA >> /tmp/sub_diag.log

cr_key="X-CrashReporter-Key: $key"
hw_model="X-Hardware-Model: $type"
# -H 'X-OS-Version: AA101TestingOffshoreda3'
echo "Submitting to $SERVER"
curl --data-binary @/tmp/sub_diag.log -H "$cr_key" -H "$hw_model" -H 'X-Routing: da2' -H 'X-Tasking-Requested: NO' -H 'Content-Type: application/vnd.apple.ips' -D /tmp/submission_diag_controller_response_headers $SERVER >/tmp/submission_diag_controller_response
