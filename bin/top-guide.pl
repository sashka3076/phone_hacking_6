#!/usr/bin/perl -w
# idle_wwdc.pl


# 8/13/08 SF: date gets output to -o file regardless of -d flag being set
# 2/23/09 SF: added support for new snowleopard top
#		- changed leopard top format string
#		- date now outputs as YYYY/MM/DD for -o and stdout

use Getopt::Std;
use POSIX qw(strftime);

use constant TO_SCREEN 	=> 0;
use constant TO_FILE 	=> 1;
use constant SINGLE 	=> 0;
use constant MULTI 	=> 1;
use constant FALSE	=> 0;
use constant TRUE	=> 1;
use constant toK	=> 1024;
use constant Mb		=> 1024;
use constant Gb		=> 1024 * Mb;
use constant MB		=> 1024;
use constant GB		=> 1024 * MB;


# modify our executable name for usage string
# -------------------------------------------
$0 =~ s|.*/(.*)$|$1|;


# Usage output
# -------------------------------------------------------------------------------------------------------------------------------------
$usage = "Usage: $0 [-o filename] [-abduIN] [-f frequency] [-r range] [-S processName] [-M processName] [-U magnitude] [-D magnitude]\n
-f: frequency in seconds (default: 10)
-b: use bytes instead of bits for network traffic (default: bits)
-U: specify the unit for displaying network traffic (*default: M)
	-- Options for 'magnitude' are [1, 2, 3] where
		1: K
		2: M
		3: G
-D: specify the unit for displaying Disk I/O (*default: MB)
	-- Options for 'magnitude' are [1, 2, 3] where
		1: K
		2: MB
		3: GB	
-o: output filename ( tab-separated data, with double-quoted column headers )
-a: append to filename specified with -o if it already exists( Default: exit if filename is present )
-h: display this usage information
-r: number of samples for averaging to look back (default: 30)
-d: Display the Date in output 
-I: Show Disk IO averages
-N: Show Network IO averages
-u: Display the currently logged in console user UID

-M: monitor 'multi-process' processes (More than one instance of processName running)
-S: monitor 'single-process' processes 


processName: process names( separated by comma) for cpu usage monitoring 
	     (processName must be the name used in top);

ex. 
	$0 -o out.txt -f2 -r5 -U3 -M smbd,mdworker -S DirectoryS,mds\n";

die "$usage\n" if !getopts('aduhINf:br:o:D:M:S:U:z', \%opts);
# -------------------------------------------------------------------------------------------------------------------------------------


# Set up signal handling
# ----------------------
$SIG{INT}  = \&handler;
$SIG{QUIT} = \&handler;
$SIG{TSTP} = \&handler;


# Show help
# ---------
if( $opts{'h'} )
{
	print "$usage\n";
	exit(0);
}


# validate output file
# --------------------
if( $opts{'o'} )
{
	$output_filename = $opts{'o'};
	print "Output file: $output_filename\n";
	die "$output_filename already exists. Choose a new name\n" if (-e $output_filename && !$opts{'a'});
	open( OUT, ">>$output_filename" ) || die "Cannot open $output_filename for output\n";
}

if( $opts{'z'} )
{
	open( DEBUG, ">/tmp/idle_debug_$$" ) || print "Could not open /tmp/idle_debug_$$ for debug logging\n";
	$debug = TRUE;
}


# Blank lines per sample is 3 on Leopard, 2 previous
# --------------------------------------------------
chomp( $vers = `sw_vers -productVersion` );
$snow = TRUE;

if( $vers =~ /10\.5/ )
{
	print "Leopard sw_vers detected: $vers\n";
	$snow = FALSE;
}
elsif( $vers =~ /10\.4/ )
{
	print "Tiger sw_vers detected: $vers\n";
	$snow = FALSE;	
}


# Setup hash for user-specified
# processes to monitor
# -----------------------------
if( $opts{'S'} )
{
	@s_procs_list = split /,/, $opts{'S'};
	foreach $procName ( @s_procs_list )
	{
		$procName = substr($procName, 0, 10) if !$snow && length($procName) > 10;
		$procName = substr($procName, 0, 16) if $snow && length($procName) > 16;
		$s_procs{ $procName } = -1;
	}
	print "Single Processes: ", "@s_procs_list\n";
}


# Setup hash for user-specified
# multi-processes to monitor
# -----------------------------
if( $opts{'M'} )
{
	@m_procs_list = split /,/, $opts{'M'};
	foreach $procName ( @m_procs_list )
	{
		$procName = substr($procName, 0, 10) if !$snow && length($procName) > 10;
		$procName = substr($procName, 0, 16) if $snow && length($procName) > 16;
		$m_procs{ $procName } = -1;
		$m_procs_seen{ $procName } = 0;
	}
	print "Mult-Processes: ", "@m_procs_list\n";
}
	

# Set sample frequency
# --------------------
if( $opts{'f'} && $opts{'f'} =~ /^\d+/ )
{
	$frequency = $opts{'f'};
	print "-f set, using $frequency-second intervals.\n";
}
else
{
	$frequency = 10;
	print "-f not set, using default $frequency-second intervals\n";
}


# Network traffic and Disk IO display opts
# ----------------------------------------
$unitstring = $opts{'b'} ? "M" : "Mb";
$d_unitstring = "MB";
print $opts{'b'} ? "-b set.  Using bytes instead of bits for network traffic\n" : "-b not set.  Using bits instead of bytes\n";
$magnitude = Mb;
$d_magnitude = MB;


# network display opt
# -------------------
if( $opts{'U'} )
{
	if( $opts{'U'} == 1 )
	{
		$unitstring = $opts{'b'} ? "K" : "kb";
		$magnitude = 1;
	}
	elsif( $opts{'U'} == 2 )
	{
		$unitstring = $opts{'b'} ? "M" : "Mb";
		$magnitude = Mb;
	}
	elsif( $opts{'U'} == 3 )
	{
		$unitstring = $opts{'b'} ? "G" : "Gb";
		$magnitude = Gb;
	}
	else
	{
		print "Bad network magnitude specified.  Using default\n";
	}	
	print "-U set.  Using $unitstring/s for network traffic\n";
}	


# disk io display opt
# -------------------
if( $opts{'D'} )
{
	if( $opts{'D'} == 1 )
	{
		$d_unitstring = "K";
		$d_magnitude = 1;
	}
	elsif( $opts{'D'} == 2 )
	{
		$d_unitstring = "MB";
		$d_magnitude = MB;
	}
	elsif( $opts{'D'} == 3 )
	{
		$d_unitstring = "GB";
		$d_magnitude = GB;
	}
	else
	{
		print "Bad disk IO magnitude specified.  Using default\n";
	}
	print "-D set.  Using $d_unitstring/s for disk I/O\n";
}


# Set range for averaging
# -----------------------
if( $opts{'r'} && $opts{'r'} =~ /^\d+$/ )
{
	$samples = $opts{'r'};
	$range = $frequency * $samples;
	print "-r set to $samples ( $range seconds )\n"; 
}
else
{
	$samples = 30;
	$range = $frequency * $samples;
	print "-r not set. Using default 30 samples ( $range seconds )\n";
}


# Command for launching top
# -------------------------
if( $snow )
{
	$top_command = "top -l0 -cd -s$frequency -stats pid,command,cpu |";
}
elsif( $vers =~ /10\.5/ ) 
{
	$top_command = "top -l0 -cd -s$frequency -p '\$aaaaa ^bbbbbbbbb \$ccccc%' -P '   PID COMMAND       CPU%' |";
}
else
{
	$top_command = "top -l0 -cd -s$frequency |";
}	

open( TOP, $top_command ) || die "Fatal: Cannot execute top\n";

$first_print = TRUE;
$kernelcpu = -1;
my %services;


# Top Match Strings Section
# ---------------------------

# common
if( $snow )
{
	$date_line	= "^(\\d+\/\\d+\/\\d+) (\\d+:\\d+:\\d+)";
	$cpu_line       = "^CPU usage: (.+)\% user, (.+)\% sys, (.+)\% idl.*\$";
	$disk_line      = "^Disks: (\\d+)\/(\\d+\\w+) read, (\\d+)\/(\\d+\\w+) written"; 
	$net_line 	= "^Networks: packets: (\\d+)\/(\\d+\\w+) in, (\\d+)\/(\\d+\\w+) out"; 
	$kernel_line    = "kernel_task\\s+(\\S+)";
}
else
{
	$cpu_line       = "^.+CPU usage: (.+)\% user, (.+)\% sys, (.+)\% idl.*\$";
	$disk_line      = "Disks:\\s+(\\d+) reads\/\\s*(\\d+)K\\s+(\\d+) writes\/(\\d+)K\\s+\$";
	$net_line       = "Networks:\\s+(\\d+) ipkts\/\\s*(\\d+)K\\s+(\\d+) opkts \/(\\d+)K\\s+\$";
	$kernel_line    = "kernel_tas\\s+(\\S+)\%";
}


# String Variables Section
# ------------------------
my $common_header1_spacing = "%-8s  %-11s  %-5s  %-5s  %-13s  %-13s  %-13s  %-13s  %-6s";
my $f_common_header1_spacing = "%-8s  %-5s %-5s  %-5s  %-5s  %-6s %-7s  %-6s %-7s %-6s %-8s %-6s %-8s  %-6s";
my $common_header2_spacing = "%-8s  %-5s %-5s  %-5s  %-5s  %-6s %-6s  %-6s %-6s  %-6s %-6s  %-6s %-6s  %-6s";

$services{ common }{ OVERLINE }  = "--------  -----------  ------------  -------------  -------------  -------------  -------------  ------";
$services{ common }{ UNDERLINE }  = "--------  ----- -----  -----  -----  ------ ------  ------ ------  ------ ------  ------ ------  ------";

$services{ common }{ HEADER1 } = sprintf( $common_header1_spacing, 
		"", "CPU usage:", "", "$range-s", "Reads/sec:", "Writes/sec:", "Net in/sec:", "Net out/sec:", "kernel");

$services{ common }{ F_HEADER1 } = sprintf( $f_common_header1_spacing, 
		"\"\"", "\"CPU\"", "\"usage:\"", "\"\"", "\"$range-s\"", "\"Reads/\"", "\"sec:\"", 
		"\"Writes/\"", "\"sec:\"", "\"Net\"", "\"in/sec:\"", "\"Net\"", "\"out/sec:\"", "\"kernel\"");

$services{ common }{ HEADER2 }  = sprintf( $common_header2_spacing, 
		"Time:", "user", "sys", "Idle", "avg.", "number", $d_unitstring, "number", $d_unitstring, "pkts", $unitstring, "pkts", $unitstring, "CPU%");

$services{ common }{ F_HEADER2 } = sprintf( $common_header2_spacing, 
		"\"Time:\"", "\"user\"", "\"sys\"", "\"Idle\"", "\"avg.\"", "\"number\"", "\"$d_unitstring\"", 
		"\"number\"", "\"$d_unitstring\"", "\"pkts\"", "\"$unitstring\"", "\"pkts\"", "\"$unitstring\"", "\"CPU%\"");

# Console user
# ------------
if( $opts{'u'} )
{
	$services{ console }{ OVERLINE } = "  -----";
	$services{ console }{ UNDERLINE } = "  -----";

	$services{ console }{ HEADER1 } = sprintf( "  %-5s", "" );
	$services{ console }{ F_HEADER1 } = sprintf( "  %-5s", "\"\"" );

	$services{ console }{ HEADER2 } = sprintf( "%-7s", "  UID:" );
	$services{ console }{ F_HEADER2 } = sprintf( "%-7s", "  \"UID:\"" );
}

# Date
# ----
if( $opts{'d'} )
{
	$services{ date }{ OVERLINE } = ("-" x 10)."  ";
	$services{ date }{ UNDERLINE } = ("-" x 10)."  ";
	
	$services{ date }{ HEADER1 } = sprintf( "%-10s  ", "" );
	# $services{ date }{ F_HEADER1 } = sprintf( "%-10s  ", "\"\"" );

	$services{ date }{ HEADER2 } = sprintf( "%-10s  ", "Date:" );
	# $services{ date }{ F_HEADER2 } = sprintf( "%-10s  ", "\"Date:\"" );
}

# SF: pulled out of block above so that date is printed to -o file
# automatically
$services{ date }{ F_HEADER1 } = sprintf( "%-10s  ", "\"\"" );
$services{ date }{ F_HEADER2 } = sprintf( "%-10s  ", "\"Date:\"" );

# Network Aves
# ------------
if( $opts{'N'} )
{
        $services{ NET }{ OVERLINE }  = "  ------  ------  ------";
        $services{ NET }{ UNDERLINE } = "  ------  ------  ------";

        $services{ NET }{ HEADER1 } = sprintf( "  %-6s  %-6s  %-6s", "NetIn", "NetOut", "NetTot");

        $services{ NET }{ F_HEADER1 } = sprintf( "  %-7s  %-7s  %-7s", "\"Net In\"", "\"Net Out\"", "\"Net Tot\"");

        $services{ NET }{ HEADER2 } = sprintf( "  %-6s  %-6s  %-6s", "ave", "ave", "ave");

        $services{ NET }{ F_HEADER2 } = sprintf( "  %-7s  %-7s  %-7s", "\"ave\"", "\"ave\"", "\"ave\"");
}

# Disk Aves
# ---------
if( $opts{'I'} )
{
        $services{ DISK }{ OVERLINE }  = "  ------  ------  ------";
        $services{ DISK }{ UNDERLINE } = "  ------  ------  ------";

        $services{ DISK }{ HEADER1 } = sprintf( "  %-6s  %-6s  %-6s", "DiskRd", "DiskWr", "DskTot");

        $services{ DISK }{ F_HEADER1 } = sprintf( "  %-7s  %-7s  %-7s", "\"Disk Rd\"", "\"Disk Wr\"", "\"DiskTot\"");

        $services{ DISK }{ HEADER2 } = sprintf( "  %-6s  %-6s  %-6s", "ave", "ave", "ave");

        $services{ DISK }{ F_HEADER2 } = sprintf( "  %-7s  %-7s  %-7s", "\"ave\"", "\"ave\"", "\"ave\"");
}	


# Process top output
# ------------------
while( <TOP> )
{
	# Common Lines
	# ------------
	if( /$kernel_line/ )
	{
		$kernelcpu = $1;

		if( $debug )
		{
			print DEBUG "$_";
			print DEBUG "kernel_task cpu: *$kernelcpu*\n";
		}

		# kernel_task should be last line of every sample
		# so let's process the parsed sample now
		update_avgs();
		update_out_strings( \%services );
		print_report( \%services, $unitstring );
	}
	elsif( $snow && /$date_line/ )
	{
		$the_date = $1;
		$currtime = $2;
	}
	elsif( /$cpu_line/ )
	{
		($usertime, $systime, $idletime) = ($1, $2, $3);
	}
	elsif( /$disk_line/ )
	{
		($diskreads, $disk_reads_size) = ($1, $2);
		($diskwrites, $disk_writes_size) = ($3, $4);
	}
	elsif( /$net_line/ )
	{
		($netpacketsin, $netdatain) = ($1, $2);
		($netpacketsout, $netdataout) = ($3, $4);
	}


	# Extra Procs lines
	# -----------------
	foreach $procName ( keys %s_procs )
	{
		$proc_match = "$procName\\s+(.+)";

		if( $debug )
		{
			print DEBUG "MATCHING STRING: *$proc_match*\n";
		}

		$proc_match .= "\%" if !$snow;

		if( /$proc_match/ ) 	
		{
			$s_procs{ $procName } = $1;
			last;
		}		

	}

	foreach $procName ( keys %m_procs )
	{
		$proc_match = "$procName\\s+(.+)";
		if( $debug )
		{
			print DEBUG "MATCHING STRING: *$proc_match*\n";
		}
		$proc_match .= "\%" if !$snow;

		if( /$proc_match/ ) 	
		{
			$m_procs{ $procName } = 0 if $m_procs{ $procName } == -1;
			$m_procs{ $procName } += $1;
			$m_procs_seen{ $procName }++;
			last;
		}		

	}


} # end while( <TOP> )


sub update_avgs
{
	$idleavg = 0;


	# Update idle-time
	# ----------------
	shift @idle if (@idle == $samples);
	push( @idle, $idletime);	

	foreach( @idle )
	{
		$idleavg += $_;
	}

	$idleavg /= @idle;

	# Update disk IO based on magnitude
	# ---------------------------------
	if( $snow )
	{
		$disk_reads_size = dehumanize( $disk_reads_size );
		$disk_writes_size = dehumanize( $disk_writes_size );
	
		# turn into KB, since pre-snow used KB by default
		$disk_reads_size /= toK;
		$disk_writes_size /= toK;
	}
	$disk_reads_size /= $d_magnitude;
	$disk_writes_size /= $d_magnitude;

	if( $opts{'I'} )
	{
		( $diskR_ave, $diskW_ave ) = (0,0);

		# Update Disk Write average
		# -------------------------
		shift @diskWrites if (@diskWrites == $samples);
		push( @diskWrites,  $disk_writes_size / $frequency  );

		foreach( @diskWrites )
		{
			$diskW_ave += $_;
		}
		
		$diskW_ave /= @diskWrites;


		# Update Disk Read Average
		# ------------------------
		shift @diskReads if (@diskReads == $samples);
		push( @diskReads, $disk_reads_size / $frequency );
		
		foreach( @diskReads )
		{
			$diskR_ave += $_;
		}
		
		$diskR_ave /= @diskReads;

		$disk_total = $diskR_ave + $diskW_ave;	
	}


	# Update Network Averages
	# -----------------------

	if( $snow )
	{
		$netdatain = dehumanize( $netdatain );
		$netdataout = dehumanize( $netdataout );

		# turn into Kb since pre-Snow used K by default
		$netdatain /= toK;
		$netdataout /= toK;
	}

	# Set Bytes or Bits
	# -----------------
	if( !$opts{'b'} )
	{
		$netdatain *= 8;
		$netdataout *= 8;
	}

	# Update net traffic based on magnitude
	# -------------------------------------
	$netdatain /= $magnitude;
	$netdataout /= $magnitude;

	if( $opts{'N'} )
	{

		( $netIn_ave, $netOut_ave ) = (0,0);

		# Update Network In Average
		# -------------------------
		shift @netin if( @netin == $samples );
		push( @netin, ($netdatain / $frequency) );

		foreach( @netin )
		{
			$netIn_ave += $_;
		}
		$netIn_ave /= @netin;

		# Update Network Out Average
		# --------------------------
		shift @netout if( @netout == $samples );
		push( @netout, ($netdataout / $frequency) );
		
		foreach( @netout )
		{
			$netOut_ave += $_;
		}
		$netOut_ave /= @netout;
				
		$net_data_total = $netIn_ave + $netOut_ave;
	}

} # end update_avgs()


sub update_out_strings
{
	my( $services ) = shift;

	my( $common_spacing, $f_outCommon );

	if( !$snow )
	{
		$the_date = strftime "%Y/%m/%d", localtime;
		$currtime = strftime "%H:%M:%S", localtime;
	}

	$common_spacing = "%08s  %5.1f %5.1f  %5.1f  %5.1f  %6d %6.1f  %6d %6.1f  %6d %6.1f  %6d %6.1f  %6.1f";
	$services->{ common }{ OUTPUT } = sprintf ( $common_spacing ,
		$currtime,
		$usertime, $systime, $idletime, $idleavg,
		$diskreads / $frequency,
		$disk_reads_size / $frequency,
		$diskwrites / $frequency,
		$disk_writes_size / $frequency,
		$netpacketsin / $frequency,
		$netdatain / $frequency,
		$netpacketsout / $frequency,
		$netdataout / $frequency, $kernelcpu );

	$f_outCommon = $services->{ common }{ OUTPUT };
	$f_outCommon =~ s/K//g;

	$services->{ common }{ F_OUTPUT } = $f_outCommon;

	if( $opts{'I'} )
        {
                $services->{ DISK }{ OUTPUT } = sprintf( "  %6.1f  %6.1f  %6.1f", $diskR_ave, $diskW_ave, $disk_total);
                $services->{ DISK }{ F_OUTPUT } = $services->{ DISK }{ OUTPUT };
        }

	if( $opts{'N'} )
        {
                $services->{ NET }{ OUTPUT } = sprintf( "  %6.1f  %6.1f  %6.1f", $netIn_ave, $netOut_ave, $net_data_total);
                $services->{ NET }{ F_OUTPUT } = $services->{ NET }{ OUTPUT };
        }

	# SF: output to -o file
	# whether -d is specified or not
	# ------------------------------
	if( $opts{'d'} )
	{
		$services->{ date }{ OUTPUT } = sprintf( "%-10s  ", "$the_date");
	}

	$services->{ date }{ F_OUTPUT } = sprintf("%s  ", $the_date);

	if( $opts{'u'} )
	{
		my $uid = get_console_user();
		$services->{ console }{ OUTPUT } = sprintf( "  %5s", $uid );
		$services->{ console }{ F_OUTPUT } = $services->{ console }{ OUTPUT };
	}

} # end update_out_strings()


sub print_report
{
	my ( $services, $unitstring ) = @_;
	my ($f_outCommon, $f_web_out, $f_mail_out);
	my ($f_nfs_out, $f_qtss_out, $f_smb_out, $name);

	# print header every 20 times
	if( !$count )
	{
		# OVERLINE
		# --------
		print $services->{ date }{ OVERLINE } if $opts{'d'};
		print $services->{ common }{ OVERLINE };
		print $services->{ console }{ OVERLINE } if $opts{'u'};	
		print $services->{ DISK }{ OVERLINE } if $opts{'I'};	
		print $services->{ NET }{ OVERLINE } if $opts{'N'};	

		foreach $proc ( sort keys %s_procs )
		{
			print get_overline( $proc, SINGLE );
		}

		foreach $proc ( sort keys %m_procs )
		{
			print get_overline( $proc, MULTI );
		}
		
		print "\n";


		# HEADER LINE 1
		# -------------
		print $services->{ date }{ HEADER1 } if $opts{'d'};
		print $services->{ common }{ HEADER1 };
		print $services->{ console }{ HEADER1 } if $opts{'u'};
		print $services->{ DISK }{ HEADER1 } if $opts{'I'};
		print $services->{ NET }{ HEADER1 } if $opts{'N'};
		
		if( $first_print && $opts{'o'} )
		{
			# print OUT $services->{ date }{ F_HEADER1 } if $opts{'d'};
			print OUT $services->{ date }{ F_HEADER1 };
			print OUT $services->{ common }{ F_HEADER1 };
			print OUT $services->{ console }{ F_HEADER1 } if $opts{'u'};
			print OUT $services->{ DISK }{ F_HEADER1 } if $opts{'I'};
			print OUT $services->{ NET }{ F_HEADER1 } if $opts{'N'};
		}

		foreach $proc ( sort keys %s_procs )
		{
			print get_header1( $proc, TO_SCREEN, SINGLE );
			print OUT get_header1( $proc, TO_FILE, SINGLE ) if $first_print && $opts{'o'};
		}
		foreach $proc ( sort keys %m_procs )
		{
			print get_header1( $proc, TO_SCREEN, MULTI );
			print OUT get_header1( $proc, TO_FILE, MULTI ) if $first_print && $opts{'o'};
		}
		print "\n";
		print OUT "\n" if $first_print && $opts{'o'};
		

		# HEADER LINE 2
		# -------------
		print $services->{ date }{ HEADER2 } if $opts{'d'};
		print $services->{ common }{ HEADER2 };
		print $services->{ console }{ HEADER2 } if $opts{'u'};
		print $services->{ DISK }{ HEADER2 } if $opts{'I'};
		print $services->{ NET }{ HEADER2 } if $opts{'N'};


		if( $first_print && $opts{'o'} )
		{
			# print OUT $services->{ date }{ F_HEADER2 } if $opts{'d'};
			print OUT $services->{ date }{ F_HEADER2 };
			print OUT $services->{ common }{ F_HEADER2 };
			print OUT $services->{ console }{ F_HEADER2 } if $opts{'u'};
			print OUT $services->{ DISK }{ F_HEADER2 } if $opts{'I'};
			print OUT $services->{ NET }{ F_HEADER2 } if $opts{'N'};
		}

		foreach $proc ( sort keys %s_procs )
		{
			print get_header2( $proc, TO_SCREEN, SINGLE );
			print OUT get_header2( $proc, TO_FILE, SINGLE ) if $first_print && $opts{'o'};
		}

		foreach $proc ( sort keys %m_procs )
		{
			print get_header2( $proc, TO_SCREEN, MULTI );
			print OUT get_header2( $proc, TO_FILE, MULTI ) if $first_print && $opts{'o'};
		}
		print "\n";
		print OUT "\n" if $first_print && $opts{'o'};
		
		# UNDERLINE
		# ---------
		print $services->{ date }{ UNDERLINE } if $opts{'d'};
		print $services->{ common }{ UNDERLINE };
		print $services->{ console }{ UNDERLINE } if $opts{'u'};	
		print $services->{ DISK }{ UNDERLINE } if $opts{'I'};	
		print $services->{ NET }{ UNDERLINE } if $opts{'N'};	

		foreach $proc ( sort keys %s_procs )
		{
			print get_underline( $proc, SINGLE );
		}

		foreach $proc ( sort keys %m_procs )
		{
			print get_underline( $proc, MULTI );
		}
		print "\n";
	}

	# Print the numbers
	# -----------------
	print $services->{ date }{ OUTPUT } if $opts{'d'};
	print $services->{ common }{ OUTPUT };
	print $services->{ console }{ OUTPUT } if $opts{'u'};
	print $services->{ DISK }{ OUTPUT } if $opts{'I'};
	print $services->{ NET }{ OUTPUT } if $opts{'N'};

	# Print the number to FILE
	# ------------------------
	if( $opts{'o'} )
	{
		# print OUT $services->{ date }{ F_OUTPUT } if $opts{'d'};
		print OUT $services->{ date }{ F_OUTPUT };
		print OUT $services->{ common }{ F_OUTPUT };
		print OUT $services->{ console }{ F_OUTPUT } if $opts{'u'};
		print OUT $services->{ DISK }{ F_OUTPUT } if $opts{'I'};
		print OUT $services->{ NET }{ F_OUTPUT } if $opts{'N'};
	}

	foreach $proc ( sort keys %s_procs )
	{
		$new_out = get_output( $proc, SINGLE );
		print $new_out;
		print OUT $new_out if $opts{'o'};
	}

	foreach $proc ( sort keys %m_procs )
	{
		$new_out = get_output( $proc, MULTI );
		print $new_out;
		# SF: this is a bug for sure
		# print OUT $new_out && $opts{'o'};
		print OUT $new_out if $opts{'o'};
	}

	print "\n";
	print OUT "\n" if $opts{'o'};
	
	$count = 0 if (++$count == 20);
	$first_print = FALSE;

	clear_procs();

} # end print_report();


sub get_console_user
{
	my ($dev_console_owner, $console_owner, $id_info, $uid);
	
	$dev_console_owner 	= `ls -al /dev/console`;
	$console_owner		= (split '\s+', $dev_console_owner)[2];
	$id			= `id $console_owner`;
	$uid			= $1 if ( $id =~ /uid=(\d+)/ );

	return $uid;
}


sub clear_procs
{
	foreach( keys %s_procs )
	{
		$s_procs{ $_ } = -1;
	}

	foreach( keys %m_procs )
	{
		$m_procs_seen{ $_ } = 0;
		$m_procs{ $_ } = -1;
	}
}


sub get_overline
{
	my ($name,$isMulti) = @_;

	if( $isMulti )
	{
		return sprintf("  %s", "-" x (length($name)==10 ? 10 : 9) );
	}
	elsif( length( $name ) < 5 )
	{
		return sprintf("  %s", "-" x 5);
	}	
	else
	{
		return sprintf("  %s", "-" x length( $name ));
	}
}


sub get_header1
{
	my ($name, $toFile, $isMulti) = @_;
	my $str;
	
	if( $isMulti )
	{
		$str =  $toFile ?  sprintf("  %-*s %-2s", , length($name), "\"".$name."\"", "\"\"") :
				sprintf("  %-*s", length($name)==10 ? 10 : 9, $name ); 
	}
	elsif( length( $name ) < 5 )
	{ 
		$str = $toFile ?  sprintf("  %-5s", "\"".$name."\"" ) :
				sprintf("  %-5s", $name ); 
	}
	else
	{
		$str = $toFile ? sprintf("  %-*s", length( $name ), "\"".$name."\"") :
				sprintf("  %-*s", length( $name ), $name);
	}
	return $str;
}


sub get_header2
{
	my ($name, $toFile, $isMulti) = @_;
	my $str;

	if( $isMulti )
	{
		$str = $toFile ? sprintf("  %-*s %-5s", length($name)==10 ? 4 : 3, "\"#\"", "\"CPU%\"") :
			sprintf("  %-*s %-5s", length($name)==10 ? 4 : 3, "#", "CPU%");
	}
	elsif( length( $name ) < 5 )
	{ 
		$str = $toFile ? sprintf("  %-5s", "\"CPU%\"") :
			sprintf("  %-5s", "CPU%");
	}
	else
	{
		$str = $toFile ? sprintf("  %-*s", length($name), "\"CPU%\"") :
			sprintf("  %-*s", length( $name ), "CPU%");
	}
	return $str;
}
		

sub get_underline
{
	my ($name, $isMulti) = @_;

	if( $isMulti )
	{
		return sprintf("  %s %s", "-" x (length($name)==10 ? 4 : 3), "-" x 5);
	}
	elsif( length( $name ) < 5 )
	{ 
		return sprintf("  %s", "-" x 5);
	}
	else
	{
		return sprintf("  %s", "-" x length( $name ));
	}
}	


sub get_output
{
	my ($name, $isMulti) = @_;
	
	if( $isMulti )
	{
		return sprintf("  %*d %5.1f", length($name)==10  ? 4 : 3, $m_procs_seen{ $name }, $m_procs{ $name });
	}
	elsif( length( $name ) < 5 )
	{
		return sprintf("  %5.1f", $s_procs{ $name });
	}
	else
	{
		return sprintf("  %*.1f", length($name), $s_procs{ $name });
	}
}


sub dehumanize
{
	my $size_string = shift;
	my ($val, $unit) = ($1,$2) if $size_string =~ /(\d+)(\w+)/;
	my $ret;
	
	if( $debug )
	{
		print DEBUG "dehumanize: passed in: $size_string val: $val unit: $unit\n";
	}
	if( $unit eq "B" )
	{
		$ret = $val;
	}
	elsif( $unit eq "K" )
	{
		$ret = $val * toK;
	}
	elsif( $unit eq "M" )
	{
		$ret = $val * toK * MB;
	}
	elsif( $unit eq "G" )
	{
		$ret = $val * toK * GB;
	}
	else{
		$ret = -1;
	}

	if( $debug ){ print DEBUG "Returning: $ret\n" }

	return $ret;
}

sub handler
{
	my ($sigtype) = shift;	

	print "\nClosing TOP...\n";
	print "Closing output file: $opts{'o'}\n" if $opts{'o'};

	close( TOP );
	close( OUT ) if $opts{'o'};

	$SIG{$sigtype} = "DEFAULT";
        kill $sigtype, $$;

}

	
