#!/usr/local/bin/luatrace -s

-- cpu-qos-breakdown.lua
-- shows CPU time spent by XCPM 'QoS' tier by command name
-- author: Matt Jacobson

qos_names = {}
qos_names[0] = "NORMAL"
qos_names[1] = "BACKGROUND"
qos_names[2] = "RT"
qos_names[3] = "RT_LONG"
qos_names[4] = "KERNEL"
qos_names[5] = "TTIER1"
qos_names[6] = "TTIER2"
qos_names[7] = "TTIER3"
qos_names[8] = "TTIER4"
qos_names[9] = "TTIER5"
qos_names[10] = "GRAPHICS_SERVER"
qos_names[11] = "IDLE"

CPUPM_PST_QOS_SWITCH=0x5310250
MACH_IDLE=0x1400024

cur_qos = {}
switch_time = {}
cur_proc = {}
cur_thread = {}

qos_execution = {}

function record_execution(command, threadid, timespent, qos)
	if qos_execution[qos] == nil then
		qos_execution[qos] = {}
	end

	if qos_execution[qos][command] == nil then
		qos_execution[qos][command] = 0
	end

	qos_execution[qos][command] = qos_execution[qos][command] + timespent
end

trace.single(CPUPM_PST_QOS_SWITCH, function(tp)
	if cur_qos[tp.cpuid] ~= nil then
		local timespent = (tp.timestamp - switch_time[tp.cpuid])

--		printf("cpu %u: process '%s' [%x] for %u ns at qos %u\n", tp.cpuid, cur_proc[tp.cpuid], cur_thread[tp.cpuid], timespent, cur_qos[tp.cpuid])

		record_execution(cur_proc[tp.cpuid], cur_thread[tp.cpuid], timespent, cur_qos[tp.cpuid])
	end

	cur_qos[tp.cpuid] = tp.arg2
	switch_time[tp.cpuid] = tp.timestamp
	cur_proc[tp.cpuid] = tp.command
	cur_thread[tp.cpuid] = tp.threadid
end)

trace.single(MACH_IDLE, function(tp)
	if trace.debugid_is_end(tp.debugid) ~= true then
		return
	end

	if cur_qos[tp.cpuid] ~= nil then
		local timespent = (tp.timestamp - switch_time[tp.cpuid])

--		printf("cpu %u: process '%s' [%x] for %u ns at qos %u\n", tp.cpuid, cur_proc[tp.cpuid], cur_thread[tp.cpuid], timespent, cur_qos[tp.cpuid])
--		printf("cpu %u: going idle\n", tp.cpuid)

		record_execution(cur_proc[tp.cpuid], cur_thread[tp.cpuid], timespent, cur_qos[tp.cpuid])		
	end

	cur_qos[tp.cpuid] = nil
	switch_time[tp.cpuid] = nil
	cur_proc[tp.cpuid] = nil
	cur_thread[tp.cpuid] = nil
end)

trace.set_completion_handler(function ()
	for qos, procs in pairsbykey(qos_execution) do
		printf("qos '%s' (%u)\n", qos_names[qos], qos)

		local total = 0

		for proc, time in pairsbyvalue(procs) do
			printf("\t%30s %30u ns\n", proc, time)

			total = total + time
		end

		printf("\n\t%30s %30u ns\n\n", "TOTAL", total)
	end	
end)
