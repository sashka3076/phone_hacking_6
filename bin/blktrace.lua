#!/usr/local/bin/luatrace -s 

do
	local timeofday = darwin.gettimeofday()
	local version = darwin.version()
	printf("# %s.%06d blktrace : v=%d\n",
		os.date("%Y%m%dT%H%M%S", timeofday.sec), timeofday.usec,
		version)
end

if opts.mount then
	root_dev = darwin.stat(opts.mount)
end

if root_dev then
	local timeofday = darwin.gettimeofday()
	local device_name = darwin.devname(root_dev.dev)
	local device_size = darwin.iomediainfo(device_name, "Size")
	local device_block_size = darwin.iomediainfo(device_name, "Preferred Block Size")
	if (not device_name) or (not device_size) or (not device_block_size) then return end

	printf("# %s.%06d %s : dev=%s size=%d block_size=%d\n",
		   os.date("%Y%m%dT%H%M%S", timeofday.sec),
		   timeofday.usec, "Device Info",
		   device_name, device_size, device_block_size)
end


DBG_READ = 0x8
DBG_ASYNC = 0x10
DBG_META = 0x20
DBG_PAGING = 0x40
DBG_PASSIVE = 0x100
DBG_NOCACHE = 0x200
DBG_THROTTLE_MASK = 0xF00
DBG_THROTTLE_SHIFT = 8

parse_debugid = function(buf)
	if bit32.band(buf.debugid, 0x8) == DBG_READ then
		buf.direction = "Rd"
	else
		buf.direction = "Wr"
	end

	if bit32.band(buf.debugid, 0x60) == 0x00 then
		buf.kind = "Data"
	elseif bit32.band(buf.debugid, 0x60) == DBG_PAGING then
		buf.kind = "Page"
	elseif bit32.band(buf.debugid, 0x60) == DBG_META then
		buf.kind = "Meta"
	else
	    buf.kind = "Unkn"
	end

	if bit32.band(buf.debugid, DBG_ASYNC) == DBG_ASYNC then
		buf.async = true
	end

	if bit32.band(buf.debugid, DBG_PASSIVE) == DBG_PASSIVE then
		buf.passive = true
	end

	if bit32.band(buf.debugid, DBG_NOCACHE) == DBG_NOCACHE then
		buf.nocache = true
	end

	buf.throttle = bit32.rshift(bit32.band(trace.debugid_code(buf.debugid), DBG_THROTTLE_MASK), DBG_THROTTLE_SHIFT)

	buf.block = buf.arg3
end

DBG_HFS_UPDATE_ACCTIME   = 0x01
DBG_HFS_UPDATE_MODTIME   = 0x02
DBG_HFS_UPDATE_CMGTIME   = 0x04
DBG_HFS_UPDATE_MODIFIED  = 0x08
DBG_HFS_UPDATE_FORCE     = 0x10
DBG_HFS_UPDATE_DATEADDED = 0x20

hfs_update_string = function(tstate)
	return string.format("%s%s%s%s%s%s",
	   bit32.band(tstate,DBG_HFS_UPDATE_ACCTIME) == DBG_HFS_UPDATE_ACCTIME and "a" or "_",
	   bit32.band(tstate,DBG_HFS_UPDATE_MODTIME) == DBG_HFS_UPDATE_MODTIME and "m" or "_",
	   bit32.band(tstate,DBG_HFS_UPDATE_CMGTIME) == DBG_HFS_UPDATE_CMGTIME and "c" or "_",
	   bit32.band(tstate,DBG_HFS_UPDATE_MODIFIED) == DBG_HFS_UPDATE_MODIFIED and "M" or "_",
	   bit32.band(tstate,DBG_HFS_UPDATE_FORCE) == DBG_HFS_UPDATE_FORCE and "F" or "_",
	   bit32.band(tstate,DBG_HFS_UPDATE_DATEADDED) == DBG_HFS_UPDATE_DATEADDED and "D" or "_")
end

modified_metadata_blocks = {}
in_flight_ios = {}
in_flight_pushes = {}
outstanding_hfs_updates = {a=0,m=0,c=0,M=0,F=0,D=0}

dkio_callback = function(buf)
	-- function start, special for dkio trace codes
	if bit32.band(buf.debugid, 4) == 0 then
		if (root_dev == nil or root_dev.dev == buf.arg2) then
			in_flight_ios[buf.arg1p] = buf
			buf.cause = in_flight_pushes[buf.threadid]
		else
			-- don't leak metadata blocks on other devices
			modified_metadata_blocks[buf.arg3] = nil
		end
		return
	end

	-- Load the corresponding start event
	local start_buf = in_flight_ios[buf.arg1p]
	if not start_buf then return end
	in_flight_ios[buf.arg1p] = nil

	parse_debugid(start_buf)

	local duration = (buf.timestamp - start_buf.timestamp) / 1000000000
	local size = start_buf.arg4 - buf.arg3

	if start_buf.kind == "Meta" and start_buf.direction == "Wr" then
		local mod = modified_metadata_blocks[start_buf.block]
		if mod then
			modified_metadata_blocks[start_buf.block] = nil
			start_buf.command = mod
		end
	end

	local throttle_str = (start_buf.throttle > 0 and string.format("T%d",start_buf.throttle)) or "__"

	cause = ""
	if start_buf.direction == "Wr" and start_buf.cause ~= nil then
		cause = string.format(" c=%s", start_buf.cause)
	end
	if start_buf.direction == "Wr" and start_buf.kind == "Meta" then
		t = 0
		for _, v in pairs (outstanding_hfs_updates) do t = t + v end
		if t > 0 then
			cause = cause .. string.format(" m=a%dm%dc%dM%dF%dD%d",
				outstanding_hfs_updates.a, outstanding_hfs_updates.m,
				outstanding_hfs_updates.c, outstanding_hfs_updates.M,
				outstanding_hfs_updates.F, outstanding_hfs_updates.D)
		   outstanding_hfs_updates = {a=0,m=0,c=0,M=0,F=0,D=0}
		end
	end
	
	local filename = lookups[buf.arg2p] or ""
	if opts.sanitize_paths and filename ~= "" then
		filename = darwin.sanitize_path(filename)
	end

	printf("%s.%06d %01.6f %-16s 0x%06x/%02d %2s%4s [%s%s%s%s] B=0x%08x S=0x%08x%s %s\n",
		   os.date("%Y%m%dT%H%M%S", start_buf.walltime),
		   start_buf.walltime_usec,
		   duration, start_buf.command,
		   start_buf.threadid, start_buf.cpuid,
		   start_buf.direction, start_buf.kind,
		   start_buf.async and "_" or "S",
		   start_buf.passive and "P" or "_",
		   start_buf.nocache and "N" or "_",
		   throttle_str,
		   start_buf.block, size, cause, filename)
end

modify_block_callback = function(buf)
	modified_metadata_blocks[buf.arg2] = buf.command;
end

DKIOCUNMAP = 0x8010641f
DKIOCSYNCHRONIZECACHE = 0x20006416

in_flight_ioctls = {}

ioctl_callback = function(buf)
	if buf.arg2 ~= DKIOCUNMAP and buf.arg2 ~= DKIOCSYNCHRONIZECACHE then
		return
	end

	if trace.debugid_is_start(buf.debugid) then
		if buf.arg2 == DKIOCUNMAP then
			buf.operation = "IOTrim"
			buf.extents = {}
		elseif buf.arg2 == DKIOCSYNCHRONIZECACHE then
			buf.operation = "IOSync"
		end

		if (root_dev == nil or root_dev.dev == buf.arg1) then
			in_flight_ioctls[buf.threadid] = buf
		end

		return
	elseif not trace.debugid_is_end(buf.debugid) then
		return
	end

	local start_buf = in_flight_ioctls[buf.threadid]
	if not start_buf then return end
	in_flight_ioctls[buf.threadid] = nil

	if start_buf.arg1 ~= buf.arg1 or start_buf.arg2 ~= buf.arg2 then
		-- Somehow our start/end tracking failed ...
		return
	end

	local data = ""
	if start_buf.arg2 == DKIOCUNMAP then
		for i,v in ipairs(start_buf.extents) do
			data = data .. string.format("0x%x:0x%x ", v.block, v.length)
			-- would be super great to have a join function here
		end
	end

	local duration = (buf.timestamp - start_buf.timestamp) / 1000000000

	printf("%s.%06d %01.6f %-16s 0x%06x/%02d %-6s %s\n",
		   os.date("%Y%m%dT%H%M%S", start_buf.walltime),
		   start_buf.walltime_usec,
		   duration, start_buf.command,
		   start_buf.threadid, start_buf.cpuid,
		   start_buf.operation, data)
end

trim_callback = function(buf)
	local start_buf = in_flight_ioctls[buf.threadid]
	if not start_buf then return end
	start_buf.extents[#start_buf.extents + 1] = {block=buf.arg2, length=buf.arg3}
end

hfs_update_aggregate = function(buf)
	if not trace.debugid_is_end(buf.debugid) then return end

    tstate = buf.arg2

	if bit32.band(tstate,DBG_HFS_UPDATE_ACCTIME) == DBG_HFS_UPDATE_ACCTIME then
		outstanding_hfs_updates.a = outstanding_hfs_updates.a + 1
	end
	if bit32.band(tstate,DBG_HFS_UPDATE_MODTIME) == DBG_HFS_UPDATE_MODTIME then
		outstanding_hfs_updates.m = outstanding_hfs_updates.m + 1
	end
	if bit32.band(tstate,DBG_HFS_UPDATE_CMGTIME) == DBG_HFS_UPDATE_CMGTIME then
		outstanding_hfs_updates.a = outstanding_hfs_updates.c + 1
	end
	if bit32.band(tstate,DBG_HFS_UPDATE_MODIFIED) == DBG_HFS_UPDATE_MODIFIED then
		outstanding_hfs_updates.M = outstanding_hfs_updates.M + 1
	end
	if bit32.band(tstate,DBG_HFS_UPDATE_FORCE) == DBG_HFS_UPDATE_FORCE then
		outstanding_hfs_updates.F = outstanding_hfs_updates.F + 1
	end
	if bit32.band(tstate,DBG_HFS_UPDATE_DATEADDED) == DBG_HFS_UPDATE_DATEADDED then
		outstanding_hfs_updates.D = outstanding_hfs_updates.D + 1
	end
end

in_flight_updates = {}
-- XXX: It would be awesome to know the device these are on!
hfs_update_callback = function(buf)
	-- function start
	if trace.debugid_is_start(buf.debugid) then
		in_flight_updates[buf.arg1p] = buf
		return
	elseif not trace.debugid_is_end(buf.debugid) then
		return
	end

	local start_buf = in_flight_updates[buf.arg1p]
	if not start_buf then return end
	in_flight_updates[buf.arg1p] = nil

	-- We only want successful endings
	if buf.arg3 ~= 0 then return end

	local duration = (buf.timestamp - start_buf.timestamp) / 1000000000

	printf("%s.%06d %01.6f %-16s 0x%06x/%02d %-6s [%s]\n",
		   os.date("%Y%m%dT%H%M%S", start_buf.walltime),
		   start_buf.walltime_usec,
		   duration, start_buf.command,
		   start_buf.threadid, start_buf.cpuid,
		   "HfsUpd",
		   hfs_update_string(buf.arg2))
end

sleepcallback = function(notification)
	local timeofday = darwin.gettimeofday() or {sec=0, usec=0}
	if notification.action == "wake" then
		printf("# %s.%06d %s : %s/%s\n",
			   os.date("%Y%m%dT%H%M%S", timeofday.sec),
			   timeofday.usec,
			   notification["User Wake"] and "User Wake" or "Dark Wake",
			   notification["Wake Reason"],
			   notification["Wake Type"])
	else
		printf("# %s.%06d Sleep\n",
			   os.date("%Y%m%dT%H%M%S", timeofday.sec),
			   timeofday.usec)
	end
end

idlecallback = function(state)
	local timeofday = darwin.gettimeofday()
	if not timeofday then
		timeofday = {sec=0, usec=0}
	end
	printf("# %s.%06d %s\n",
		   os.date("%Y%m%dT%H%M%S", timeofday.sec),
		   timeofday.usec,
		   state == 1 and "User Active" or "User Inactive")
end

-- Track system calls so we can see why a particular IO was issued
syscall_callback = function(buf)
	if trace.debugid_is_start(buf.debugid) then
		name = darwin.syscalls[trace.debugid_code(buf.debugid)]
		in_flight_pushes[buf.threadid] = name
	elseif trace.debugid_is_end(buf.debugid) then
		in_flight_pushes[buf.threadid] = nil
	end
end

fullfsync_callback = function(buf)
	if buf.arg2 ~= 51 then return end -- check which fcntl()
	syscall_callback(buf)
end

pending_lookup_vps = {}
pending_lookups = {}
lookups = {}
vfs_lookup_callback = function(buf)
	if trace.debugid_is_start(buf.debugid) then
		local vp = buf.arg1p
		local path = darwin.ptr2str(buf.arg2p) .. darwin.ptr2str(buf.arg3p) .. darwin.ptr2str(buf.arg4p)
		pending_lookup_vps[buf.threadid] = vp
		pending_lookups[buf.threadid] = path
	else
		local path = pending_lookups[buf.threadid]
		if path ~= nil then
			local path_next = darwin.ptr2str(buf.arg1p) .. darwin.ptr2str(buf.arg2p) .. darwin.ptr2str(buf.arg3p) .. darwin.ptr2str(buf.arg4p)
			pending_lookups[buf.threadid] = path .. path_next
		end
	end

	if trace.debugid_is_end(buf.debugid) then
		local vp = pending_lookup_vps[buf.threadid]
		local path = pending_lookups[buf.threadid]
		if path ~= nil then
			pending_lookup_vps[buf.threadid] = nil
			pending_lookups[buf.threadid] = nil
			lookups[vp] = path
		end
	end
end

vfs_alias_vp_callback = function(buf)
	lookups[buf.arg2p] = lookups[buf.arg1p]
end

throttle_cause_pid = {}
throttle_level = {}

process_throttle_callback = function(buf)
	throttle_cause_pid[buf.threadid] = buf.arg1
	throttle_level[buf.threadid] = buf.arg4
end

throttled_callback = function(start_buf, end_buf)
	local duration = (end_buf.timestamp - start_buf.timestamp) / 1000000000
	local cause_pid = throttle_cause_pid[start_buf.threadid]
	throttle_cause_pid[start_buf.threadid] = nil
	local level = throttle_level[start_buf.threadid]
	throttle_level[start_buf.threadid] = nil

	-- l=${level}:${period}/${window} c=${throttle_io_count} p={causing pid}
	printf("%s.%06d %01.6f %-16s 0x%06x/%02d %-6s l=%d:%d/%d c=%d p=%d\n",
		   os.date("%Y%m%dT%H%M%S", start_buf.walltime),
		   start_buf.walltime_usec,
		   duration, start_buf.command,
		   start_buf.threadid, start_buf.cpuid,
		   "THROTL", level, start_buf.arg1, start_buf.arg2, end_buf.arg3, cause_pid)
end

in_flight_cs = {}

-- See CoreStorage/iokit/CoreStorageTimeStamps.h for these definitions
corestorage_io_callback = function(buf)
	-- IO start check
	if bit32.band(buf.debugid, 4) == 0 then
		in_flight_cs[buf.arg2p] = buf
		return
	end

	-- Load the corresponding start event
	local start_buf = in_flight_cs[buf.arg2p]
	if not start_buf then return end
	in_flight_cs[buf.arg2p] = nil
	local end_buf = buf

	local flags = bit32.band(start_buf.debugid,0xF0)
	local direction = "??"
	if bit32.band(flags,0x10) == 0x10 then
		direction = "Wr"
	else
		direction = "Wr"
	end

	local command = bit32.band(start_buf.debugid,0xFF00)
	local operation = "CS??"
	local data = ""
	if command == 0x0100 then
		operation = "CSIO"
	elseif command == 0x0200 then
		return -- SubIO, ignore for now
	elseif command == 0x0300 then
		operation = "CSMd"
	elseif command == 0x0400 then
		return -- Crypto, ignore for now
	elseif command == 0x0500 then
		operation = "CSTr"
	elseif command == 0x0600 then
		operation = "CSMg"
	end

	data = string.format(" B=0x%08x S=0x%08x", start_buf.arg3, start_buf.arg4)

	start_buf.operation = operation .. direction

	local duration = (end_buf.timestamp - start_buf.timestamp) / 1000000000

	printf("%s.%06d %01.6f %-16s 0x%06x/%02d %-6s%s\n",
		   os.date("%Y%m%dT%H%M%S", start_buf.walltime),
		   start_buf.walltime_usec,
		   duration, start_buf.command,
		   start_buf.threadid, start_buf.cpuid,
		   start_buf.operation, data)
end

corestorage_sync_callback = function(start_buf, end_buf)
	local duration = (end_buf.timestamp - start_buf.timestamp) / 1000000000

	printf("%s.%06d %01.6f %-16s 0x%06x/%02d %-6s\n",
		   os.date("%Y%m%dT%H%M%S", start_buf.walltime),
		   start_buf.walltime_usec,
		   duration, start_buf.command,
		   start_buf.threadid, start_buf.cpuid,
		   "CSSync")
end

dropped_events_callback = function()
	in_flight_ioctls = {}
	in_flight_ios = {}
	in_flight_updates = {}
	in_flight_pushes = {}
	in_flight_cs = {}
	modified_metadata_blocks = {}
	throttle_cause_pid = {}
	throttle_level = {}
	
	local timeofday = darwin.gettimeofday() or {sec=0, usec=0}
	printf("# %s.%06d %s\n",
		   os.date("%Y%m%dT%H%M%S", timeofday.sec),
		   timeofday.usec,
		   "Dropped Events")
end

trace.range(kdebug_code(3,2,0), kdebug_code(3,3,0), dkio_callback)
trace.range(kdebug_code(3,6,0), kdebug_code(3,6,1), ioctl_callback)
trace.range(kdebug_code(3,6,1), kdebug_code(3,6,2), trim_callback)
trace.range(kdebug_code(3,1,0x2000), kdebug_code(3,1,0x2001), hfs_update_aggregate)
trace.range(kdebug_code(3,1,0x2001), kdebug_code(3,1,0x2002), modify_block_callback)
trace.range(kdebug_code(0x3,0x1,0x24), kdebug_code(0x3,0x1,0x25), vfs_lookup_callback)
trace.single(kdebug_code(0x3,0x1,0x25), vfs_alias_vp_callback)

trace.single_paired(kdebug_code(3,1,97), throttled_callback)
trace.single(kdebug_code(3,0x11,2), process_throttle_callback)

if opts.corestorage then
	trace.range(kdebug_code(10,0,0), kdebug_code(10,1,0), corestorage_io_callback);
	trace.single_paired(kdebug_code(10,1,0), corestorage_sync_callback);
end

if opts.hfs_update then
	trace.range(kdebug_code(3,1,0x2000), kdebug_code(3,1,0x2001), hfs_update_callback)
end

if not opts.avoid_syscalls then
	trace.range(kdebug_code(4,0xc,0x5c), kdebug_code(4,0xc,0x5d), fullfsync_callback)
	trace.range(kdebug_code(4,0xc,0x196), kdebug_code(4,0xc,0x197), fullfsync_callback)
	syscallnums = {0x000,0x001,0x003,0x004,0x005,0x006,0x009,0x00a,0x024,0x041,0x05f,0x078,0x079,0x080,0x099,0x09a,0x0bb,0x0bc,0x0bd,0x0be,0x0c4,0x0c5,0x0c7,0x0c8,0x0c9,0x0cd,0x0d8,0x0dc,0x0dd,0x0de,0x0e1,0x0e2,0x0e3,0x115,0x117,0x118,0x119,0x13f,0x152,0x153,0x154,0x155,0x156,0x157,0x158,0x159,0x15a,0x15b,0x16c,0x18c,0x18d,0x18e,0x18f,0x195,0x196,0x198,0x19b,0x19c,0x19d,0x19e,0x19f,0x1a5,0x1b9,0x1ba}
	for i = 1, #syscallnums do
		trace.range(kdebug_code(4,0xc,syscallnums[i]), kdebug_code(4,0xc,syscallnums[i] + 1), syscall_callback)
	end
end

trace.set_dropped_events_handler(dropped_events_callback)

if darwin.sleepnotify then
    darwin.sleepnotify(sleepcallback)
end

do
	-- print initial user activity state
	local idle = darwin.notify("com.apple.system.powermanagement.useractivity", idlecallback)
	idlecallback(idle)
end
