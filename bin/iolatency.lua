#!/usr/local/bin/luatrace -s 

-- FIXME: define this in luatrace
kdebug_code = function(class, subclass, code)
	return bit32.lshift(class, 24) + bit32.lshift(subclass, 16) + bit32.lshift(code, 2)
end

lat_count = {}
lat_sum = {}

ios = {}
callback = function(buf)
	if bit32.band(buf.debugid, 4) == 0 then
		-- IO start
		ios[buf.arg1p] = buf;
		return
	end

	local start_buf = ios[buf.arg1p];
	if not start_buf then return end
	ios[buf.arg1p] = nil;

	buf.duration = (buf.timestamp - start_buf.timestamp) / 1000000

	if lat_count[start_buf.command] then
		lat_count[start_buf.command] = lat_count[start_buf.command] + 1
		lat_sum[start_buf.command] = lat_sum[start_buf.command] + buf.duration
	else
		lat_count[start_buf.command] = 1
		lat_sum[start_buf.command] = buf.duration
	end
end

trace.range(kdebug_code(3,2,0), kdebug_code(3,3,0), callback)

dropped_events_callback = function()
	ios = {}
end

trace.set_dropped_events_handler(dropped_events_callback)

darwin.timer(1000, function ()
	for key,_ in pairs(lat_count) do
		printf("%s: %f\n", key, lat_sum[key] / lat_count[key]);
	end
	printf("---\n")
end)
