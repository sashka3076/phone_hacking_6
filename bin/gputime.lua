#!/usr/local/bin/luatrace -s

-- gputime.lua
-- measures approximate GPU time by ring, by process on recent intel GT
-- author: Matt Jacobson

darwin.sysctlbyname("debug.intel.IGInterruptControl", 1)
darwin.sysctlbyname("debug.intelfb.IGInterruptControl", 1)
darwin.sysctlbyname("debug.intel.graphicsTracePointEnable", 1)
darwin.sysctlbyname("debug.intelfb.graphicsTracePointEnable", 1)

rings = {}
start_timestamps = {}
process_names = {}

total_times = {}

total_times[0] = {}
total_times[1] = {}
total_times[2] = {}

ring_names = {}
ring_names[0] = "Main ring"
ring_names[1] = "Media ring"
ring_names[2] = "Blt ring"

submit_debugid=0x612a404
interrupt_debugid=0x612a408

trace.single(submit_debugid, function(buf)
	-- arg1 is the ring number
	-- arg3 is 1 iff we will get an INTERRUPT for this submission
	-- arg4 is the submission number

	if start_time == nil then
		start_time = buf.timestamp
	end

	last_time = buf.timestamp

	if buf.arg3 ~= 1 then
		return
	end

	rings[buf.arg4] = buf.arg1
	start_timestamps[buf.arg4] = buf.timestamp
	process_names[buf.arg4] = buf.command
end)

trace.single(interrupt_debugid, function(buf)
	-- arg1 is the ring number
	-- arg2 is the submission number up to which everything has completed

	last_time = buf.timestamp

	if rings[buf.arg2] == nil or start_timestamps[buf.arg2] == nil or process_names[buf.arg2] == nil then
		return
	end

	-- TODO: for "coalesced" interrupts, consider all but the earliest sequence number to have zero duration
	for id, ring in pairs(rings) do
		if ring == buf.arg1 then
			if id <= buf.arg2 then
				if total_times[ring][process_names[id]] == nil then
					total_times[ring][process_names[id]] = 0
				end

				local timespent = 0
				if id == buf.arg2 then
					timespent = (buf.timestamp - start_timestamps[id])
				end

				-- printf("work on ring %d by process '%s' took %u ns (interrupt delta %d)\n", ring, process_names[id], timespent, buf.arg2 - id)

				total_times[ring][process_names[id]] = total_times[ring][process_names[id]] + timespent -- (buf.timestamp - start_timestamps[id])

				rings[id] = nil
				start_timestamps[id] = nil
				process_names[id] = nil
			else
				-- refresh the start timestamp for any submissions that haven't been completed, since they obviously have not started yet
				start_timestamps[id] = buf.timestamp
			end
		end
	end
end)

trace.set_completion_handler(function()
	if last_time == nil then
		return
	end

	for id, process in pairs(process_names) do
		printf("found dangling submit by '%s' at relative time %d ns\n", process, start_timestamps[id] - start_time)
	end

	total_time = last_time - start_time

	printf("%20s %15u ns\n\n", "total walltime", total_time)

	for ring, ring_total_times in pairs(total_times) do
		printf("%s (%d):\n", ring_names[ring], ring)

		for process, time in pairs(ring_total_times) do
			printf("\t%20s %15.0f%% %15u ns\n", process, time * 100 / total_time, time)
		end

		printf("\n")
	end

	darwin.sysctlbyname("debug.intel.IGInterruptControl", 0)
	darwin.sysctlbyname("debug.intelfb.IGInterruptControl", 0)
	darwin.sysctlbyname("debug.intel.graphicsTracePointEnable", 0)
	darwin.sysctlbyname("debug.intelfb.graphicsTracePointEnable", 0)
end)

