shopt -s extglob

while [[ $# > 0 ]]
do
	key="$1"
	shift

	case $key in
		-v|--allLogs)
		allLogs=1
		;;
		-b|--skipBTA)
		skipBTA=1
		;;
		-a|--AGGD)
		skipAggd=1
		;;
		-c|--CC)
		skipCC=1
		;;
		-r|--R3)
		skipR3=1
		;;
		-q|--skipLogs)
		skipLogs=1
		;;
		-x|--only)
		only=1
		;;
		*)
		echo "Unknown option: $key"
		;;
	esac
done

function chOpt()
{
	y=\$"$1"   # Name of variable (not value!).
	x=`eval "expr \"$y\" "`
	if ((x == 1)); then
		unset $1
	else
		eval "$1=1"
	fi
}

if (( only == 1)); then
	chOpt skipAggd
	chOpt skipCC
	chOpt skipR3
fi

# submission diagnostics
export now_secs=`date -ju +%s`
failures=0
warnings=0

echo "========== Submission Diagnostic Script (v1.1) ==========="
gestalt_query InverseDeviceID
gestalt_query ProductType
sw_vers
echo "Local Time:     `date`"
echo "UTC Time:       `date -jur $now_secs` (or $now_secs)"
echo "Uptime: `uptime`"
# is device opted in?
opt_in=`profilectl settings | awk 'BEGIN {x=0}; /Effective user settings/ { x=1 }; x==1 && /allowDiagnosticSubmission/ { x=2 }; x==2 && /value/ && $3=="0;" { print 0; exit }; x==2 && /value/ && $3=="1;" { print 1; exit };'`
if ((opt_in == 1)); then
	echo "Device is Opted-In [OK]"
else
	echo "Device is Opted-Out [FAIL]"
	((failures++))
fi

if [[ -z $skipAggd ]]; then
	echo "======================= Aggregated ======================="
	last_fired=`defaults read ~mobile/Library/Preferences/com.apple.aggregated.plist LastDailyTimerFiredTimeKey`
	#last_fired_day_secs=`date -jur $((last_fired * 24 * 60 * 60)) +%s`
	#echo "Last fired: $((last_fired_day_secs - now_sec * 24 * 60 * 60))"
	now_day=$((now_secs / 24 / 60 / 60))
	if ((last_fired == now_day)); then
		echo "ADDaily trigger already fired today [OK]"
	else
		echo "ADDaily trigger happened $((now_day - last_fired)) days ago [FAIL]"
		((failures++))
	fi

	last_processed=`defaults read ~mobile/Library/Preferences/com.apple.aggregated.addaily.plist LastCrashLogSerializationDateInDaysSince1970`
	if ((last_processed == now_day - 1)); then
		echo "ADDaily processed yesterday's results [OK]"
	else
		echo "ADDaily last processed results from $((now_day - last_processed)) days ago [FAIL]"
		((failures++))
	fi

	aggd_sched=`defaults read ~mobile/Library/Preferences/com.apple.aggregated.plist NextScheduledRun`
	if [ -z "$aggd_sched" ]; then
		echo "No record of aggregated schedule for addaily! [FAIL]"
		((failures++))
	else
		aggd_sched_secs=`date -ju -f "%F %T %z" "$aggd_sched" +%s`
		if ((aggd_sched_secs >= now_secs)); then
			echo "Next launch is scheduled in the future for `date -jur $aggd_sched_secs`, (in $((aggd_sched_secs - now_secs)) seconds) [OK]"
		else
			echo "Scheduled attempt expired at `date -jur $aggd_sched_secs`, ($((now_secs - aggd_sched_secs)) seconds ago) [FAIL]"
			((failures++))
		fi
	fi

	if [ -z $skipBTA ]; then
		bta_sched=`aggregatectl --checkSchedule`
		if [ -z "$bta_sched" ]; then
			echo "Unable to detect BTA Scheduling [WARN]"
			((warnings++))
		else
			next_add_secs=`date -ju -v1d -v1m -v2001y -v0H -v0M -v0S -v+${bta_sched##+([!0-9])}S +%s`
			if ((next_add_secs == 0)); then
				echo "No BTA schedule set for ADDaily! [FAIL]"
				((failures++))
			elif ((next_add_secs >= now_secs)); then
				echo "BTA schedule for ADDaily is set in the future for `date -jur $next_add_secs`, (in $((next_add_secs - now_secs)) seconds) [OK]"
			else
				echo "BTA schedule for ADDaily already expired at `date -jur $next_add_secs`, ($((now_secs - next_add_secs)) seconds ago) [FAIL]"
				((failures++))
			fi
		fi
	fi

	recent_session=`find ~mobile/Library/Logs/CrashReporter -name "log-session*" -exec basename {} \; | sort | tail -1`
	if [ -z $recent_session ]; then
		echo "No sesssion logs exist [WARN]"
		((warnings++))
		session_db_size=`stat -f"%z" ~mobile/Library/AggregateDictionary/sessionbuffer_v2`
		if ((session_db_size == 0)); then
			echo "This device does not seem to use any 3rd party apps [WARN]"
			((warnings++))
		else
			echo "session buffer has $session_db_size bytes"
		fi
	else
		recent_session_secs=`date -j -f "log-sessions-%Y-%m-%d-%H%M%S.session" "$recent_session" +%s`
		if ((now_day - (recent_session_secs / 24 / 60 / 60) <= 1)); then
			echo "Session log is recent ($(( (now_secs - recent_session_secs) / 60 / 60)) hour(s) ago) [OK]"
		else
			echo "Session log is old ($(( (now_secs - recent_session_secs) / 60 / 60)) hours ago) [WARN]"
			((warnings++))
		fi
	fi

	recent_aggd=`find ~mobile/Library/Logs/CrashReporter -name "log-agg*" -exec basename {} \; | sort | tail -1`
	if [ -z $recent_aggd ]; then
		echo "No aggd logs exist! [FAIL]"
		((failures++))
	else
		recent_aggd_secs=`date -j -f "log-aggregated-%Y-%m-%d-%H%M%S" "${recent_aggd%_*}" +%s`
		if ((now_day - (recent_aggd_secs / 24 / 60 / 60) <= 1)); then
			echo "Aggd log is recent ($(( (now_secs - recent_aggd_secs) / 60 / 60)) hour(s) ago) [OK]"
		else
			echo "Aggd log is old ($(( (now_secs - recent_aggd_secs) / 60 / 60)) hours ago) [FAIL]"
			((failures++))
		fi
	fi
fi

if [[ -z $skipCC ]]; then
	echo "===================== OTACrashCopier ====================="
	# is it hung?
	pid=`pidof OTACrashCopier`
	if [ -z $pid ]; then
		echo "OTACrashCopier is not running; therefore not hung [OK]"
	else
		echo "OTACrashCopier IS running, and possibly hung [FAIL]"
		((failures++))
	fi
	# when was last submission ?
	if [ -f ~mobile/Library/OTALogging/.last_attempted_submission_marker ]; then
		last_attempt_secs=`stat -f"%m" ~mobile/Library/OTALogging/.last_attempted_submission_marker`
		if ((now_secs - last_attempt_secs < 86400)); then
			echo "Last attempted  submission was at `date -jur $last_attempt_secs` within the past 24 hours ($((now_secs - last_attempt_secs)) seconds ago) [OK]"
		else
			echo "Last attempted  submission was at `date -jur $last_attempt_secs` EXCEEDS 24 hours retry logic ($((now_secs - last_attempt_secs)) seconds ago) [FAIL]"
			((failures++))
		fi
		if [ -f ~mobile/Library/OTALogging/.last_successful_submission_marker ]; then
		last_success_secs=`stat -f"%m" ~mobile/Library/OTALogging/.last_successful_submission_marker`
		if ((now_secs - last_success_secs < 86400)); then
			echo "Last successful submission was at `date -jur $last_success_secs` within the past 24 hours ($((now_secs - last_success_secs)) seconds ago) [OK]"
		else
			echo "Last successful submission was at `date -jur $last_success_secs` EXCEEDS 24 hour policy ($((now_secs - last_success_secs)) seconds ago) [FAIL]"
			((failures++))
		fi
	else
		echo "This device has never successfully submitted logs [FAIL]"
		((failures++))
	fi
	else
		echo "This device has never attempted to submit logs [FAIL]"
		((failures++))
	fi
	# when is the next scheduled submission?
	next_scheduled=`defaults read ~mobile/Library/Preferences/com.apple.OTACrashCopier.plist NextScheduledSubmission`
	if [[ $next_scheduled = "Locked" ]]; then
		echo "Not scheduled since first unlock [(probably) OK]"
	else
		next_scheduled_secs=`date -ju -f "%F %T %z" "$next_scheduled" +%s`
		if ((next_scheduled_secs >= now_secs)); then
			echo "Next attempt is scheduled in the future for `date -jur $next_scheduled_secs`, (in $((next_scheduled_secs - now_secs)) seconds) [OK]"
		else
			echo "Scheduled attempt expired at `date -jur $next_scheduled_secs`, ($((now_secs - next_scheduled_secs)) seconds ago) [FAIL]"
			((failures++))
		fi
	fi
	# does nsurlsession have anything scheduled?
	if [ -f ~mobile/Library/com.apple.nsurlsessiond/88FA46B3255990F9B0FE64762DE1A1751F240BC9/88FA46B3255990F9B0FE64762DE1A1751F240BC9/tasks.plist ]; then
		# this eval sets some variables created by awk
		eval `plutil -p ~mobile/Library/com.apple.nsurlsessiond/88FA46B3255990F9B0FE64762DE1A1751F240BC9/88FA46B3255990F9B0FE64762DE1A1751F240BC9/tasks.plist | awk '/\"suspendCount\"/ {print "session_suspended=" $3;}; /\"state\"/ { print "session_state=" $3;}; /\"creationTime\"/ { print "session_created=" int($3);} /12 =>/ { print "v12=" int($3);} /13 =>/ { print "v13=" int($3);} /14 =>/ { print "v14=" int($3);}  /15 =>/ { print "v15=" int($3);};'`
		# the variable indices change depending on version and device type (or something)
		# but the workload is hardcoded to a value of 131072, so anchoring on that we can find delay and duration sequentially
		if ((v12 == 131072)); then
			session_delay=$v13
			session_duration=$v14
		elif ((v13 == 131072)); then
			session_delay=$v14
			session_duration=$v15
		else
			echo "Sanity check against nsurlsessiond config failed; that version isn't compatible with this script [FAIL]"
			((failures++))
		fi
		if [ $session_delay ]; then
			# convert values from reference date (seconds since 1/1/2001) to epoch (since 1/1/1970)
			session_created_secs=`date -ju -v1d -v1m -v2001y -v0H -v0M -v0S -v+${session_created}S +%s`
			expected_delta=$((session_created_secs + session_delay - next_scheduled_secs))
			# absolute value (trick)
			expected_delta=${expected_delta#-}
			session_trigger_secs=$((session_created_secs + session_delay))
			if ((expected_delta <= 2)); then
				echo "NSURLSession scheduled for `date -jur $session_trigger_secs` (in $((session_trigger_secs - $now_secs)) seconds) matches expected time [OK]"
			else
				if ((session_trigger_secs >= $now_secs)); then
					if [[ $next_scheduled = "Locked" ]]; then
						echo "NSURLSession scheduled for `date -jur $session_trigger_secs` (in $((session_trigger_secs - $now_secs)) seconds) (but hasn't been rescheduled since first unlock) [OK]"
					else
						echo "NSURLSession scheduled for `date -jur $session_trigger_secs` (in $((session_trigger_secs - $now_secs)) seconds) does NOT match expected time (but is in the future) [(mostly) OK]"
					fi
				else
					echo "NSURLSession scheduled for `date -jur $session_trigger_secs` (in $((session_trigger_secs - $now_secs)) seconds) has EXPIRED [FAIL]"
					((failures++))
				fi
			fi
		fi
		if ((session_state==0)); then
			echo "NSURLSession task/schedule is running [OK]"
		else
		if ((session_state==1)); then
			echo "NSURLSession task/schedule is suspended [FAIL]"
		elif ((session_state==2)); then
			echo "NSURLSession task/schedule is canceling [FAIL]"
		elif ((session_state==3)); then
			echo "NSURLSession task/schedule is completed [FAIL]"
		else
			echo "NSURLSession task/schedule state is UNKNOWN($session_state) [FAIL]"
		fi
		((failures++))
	fi
	else
		echo "NSURLSession has no record of scheduling from OTACrashCopier! [FAIL]"
		((failures++))
	fi

	echo "==================== NSURLSession Info ==================="
	# is nsurlsession actively processing our request?
	killall -INFO networkd; sleep 1; syslog -k Sender networkd -k Time ge -5 | egrep -A1 "Pool name:|OTACrashCopier"
fi

if [[ -z $skipR3 ]]; then
	echo "==================== General Logs Vers ==================="
	awk -v OSV=`sw_vers | tail -1 | cut -f2` 'BEGIN { print "OS vers:     " OSV } /OS-Version/ && match($0,/\([^)]*\)/) { vers=substr($0, RSTART+1,RLENGTH-2); print PF, vers, (vers == OSV) ? "[OK]" : "[FAIL]"; nextfile }' PF="root vers:  " /var/logs/AppleSupport/general.log PF="mobile vers:" /var/mobile/Library/Logs/AppleSupport/general.log
fi

if [[ -z $skipLogs ]]; then
	echo "======================= Crash Logs ======================="
	# has it been crashing?
	if [ -z $allLogs ]; then
		find ~mobile/Library/Logs/CrashReporter -name "aggregated*"
		find ~mobile/Library/Logs/CrashReporter -name "addaily*"
		find ~mobile/Library/Logs/CrashReporter -name "OTACrashCopier*"
		find ~mobile/Library/Logs/CrashReporter -name "network*"
	else
		find -s ~mobile/Library/Logs/CrashReporter -name "*.ips*" -print -exec head -1 {} ";"
	fi
	echo "================== Aggd and Session Logs ================="
	if [ -z $allLogs ]; then
		find ~mobile/Library/Logs/CrashReporter -name "log-agg*"
		find ~mobile/Library/Logs/CrashReporter -name "log-session*"
	else
		find -s ~mobile/Library/Logs/CrashReporter -name "log-[a|s]*" -print -exec head -1 {} ";"
	fi
fi

echo "======================== Summary ========================="
if ((failures > 0)); then
	echo "$failures Failed and $warnings warning checks found"
elif ((warnings > 0)); then
	echo "$warnings warning check(s) found"
else
	echo "Everything seems cool"
fi
echo "=========================================================="
exit $failures
