#!/usr/sbin/dtrace -s
#pragma D option quiet
#pragma D option bufsize=256k

/*
 * fileio.d - Trace file IO by a particular process and aggregate by filename.
 * The aggregation truly is by file name alone (e.g. 'foo/bar' and 'baz/bar' will both
 * be accounted for under 'bar').
 * Usage: fileio.d <execname>
 */

BEGIN { 
	en = substr($$1, 0, 15);
	printf("Ready to trace execname = '%s'.\n", en);
}

io:::start / execname == en / { start[arg0] = timestamp; }

io:::done / start[arg0] / 
{
	delta = timestamp - start[arg0];
	kbytes = args[0]->b_bcount >> 10;
	is_read = args[0]->b_flags & B_READ;
	filename = args[2]->fi_name; 
	@total_io_time = sum(delta);
	start[arg0] = 0;
	req_done = 1;
}

io:::done / req_done && is_read /
{
	@read_vols[filename]  = sum(kbytes);
	@read_times[filename] = sum(delta);
	@read_sizes[kbytes]   = count();
	@total_reads          = sum(kbytes);
	req_done = 0;
}

io:::done / req_done && !is_read /
{
	@write_vols[filename]  = sum(kbytes);
	@write_times[filename] = sum(delta);
	@write_sizes[kbytes]   = count();
	@total_writes          = sum(kbytes);
	req_done = 0;
}

END {
	/* convert time aggregations to us (individual files) and ms (total) */
	normalize(@read_times, 1000);
	normalize(@write_times, 1000);
	normalize(@total_io_time, 1000000);
	
	printf("IO volumes:\n");
	printa("%50s\tR\t%@d kB\n", @read_vols);
	printf("\n");
	printa("%50s\tW\t%@d kB\n", @write_vols);
	printf("\n");

	printf("IO request sizes:\n");
	printa("%5d kB\tR\t%@d\n", @read_sizes);
	printf("\n");
	printa("%5d kB\tW\t%@d\n", @write_sizes);
	printf("\n");

	printf("IO times:\n");
	printa("%50s\tR\t%@d us\n", @read_times);
	printf("\n");
	printa("%50s\tW\t%@d us\n", @write_times);
	printf("\n");

	printa("Total reads: %@d kB\n", @total_reads);
	printa("Total writes: %@d kB\n", @total_writes);
	printa("Total IO time: %@d ms\n", @total_io_time);
}
