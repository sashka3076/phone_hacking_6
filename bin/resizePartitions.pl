#!/usr/bin/perl
# original copy in ~rgmisra/bin
use strict;

sub myHex($)
{
    # since we can encounter numbers that are too large, implement our own hex logic
    
    my ($str) = @_;
    $str =~ s|^\s*0x||;
    $str =~ s|\s*$||;
    my $value = 0;
    my $len = length($str);
    for (my $i = 0; $i < $len; $i++) {
        $value *= 16;
        my $c = substr($str, $i, 1);
        my $d = hex($c);
        $value += $d;
    }
    return $value;
}

sub humanSize($)
{
    my ($size) = @_;
    
    if ($size > 1024*1024*1024) {
        $size /= 1024*1024*1024;
        return sprintf("%.2fGiB", $size);
    }

    if ($size > 1024*1024) {
        $size /= 1024*1024;
        return sprintf("%.2fMiB", $size);
    }

    if ($size > 1024) {
        $size /= 1024;
        return sprintf("%.2fKiB", $size);
    }
    return "${size}B";
}

sub getLWVMInfo()
{
    my $info = `lwvm info`;
    
    my ($logicalSize, $blockSize, $chunkSize);
    if ($info =~ m|Logical size\s*(0x[0-9a-f]*)|s) {
        $logicalSize = myHex($1);
    }
    if ($info =~ m|Block size\s*(0x[0-9a-f]*)|s) {
        $blockSize = myHex($1);
    }
    if ($info =~ m|Chunk size\s*(0x[0-9a-f]*)|s) {
        $chunkSize = myHex($1);
    }
    
    my $parts;
    if ($info =~ m|Partitions:\s*(.*?)\s*Chunk map|s) {
        $parts = $1;
    }
    $parts .= "\n10000:\n";  # add a dummy line to simplify the logic below
    
    my @lines = split("\n", $parts);
    my %parts;
    my $curPart;
    my $curPartName;
    my $partNum = -1;
    my $partCount = 0;
    my $maxNameLen = 0;
    foreach my $line (@lines) {
        if ($line =~ m|^\s*(\d+):|) {
            if (defined($curPart)) {
                $curPart->{"byteSize"} = $curPart->{"end"} - $curPart->{"start"};
                $curPart->{"size"} = humanSize($curPart->{"byteSize"});
                $curPart->{"blockSize"} = $curPart->{"byteSize"} / $blockSize;
                $curPart->{"name"} = $curPartName;
                $parts{lc($curPartName)} = $curPart;
                $partCount++;
                my $nameLen = length($curPartName);
                if ($nameLen > $maxNameLen) { $maxNameLen = $nameLen; }
            }
            my %hash;
            $curPart = \%hash;
            $partNum = $1;
            $curPart->{"partNum"} = $partNum;
        }
        if ($line =~ m/^\s+(start|end)\s+(0x[0-9a-f]+)/) {
            $curPart->{$1} = myHex($2);
        }
        if ($line =~ m/^\s+name\s+(.*)/) {
            $curPartName = $1;
        }
    }
    
    return ($logicalSize, $blockSize, $chunkSize, $partCount, $maxNameLen, %parts);
}

sub sizeInBlocks($$)
{
    my ($size, $blockSize) = @_;
    
    my $sizeInBytes;
    if ($size =~ m|b$|i) {
        # size is in bytes
        $sizeInBytes = $size + 0; # coerce to a number
    } elsif ($size =~ m|k$|i) {
        # size is in KiB
        $sizeInBytes = $size * 1024;
    } elsif ($size =~ m|m$|i) {
        # size is in MiB
        $sizeInBytes = $size * 1024 * 1024;
    } elsif ($size =~ m|g$|i) {
        # size is in GiB
        $sizeInBytes = $size * 1024 * 1024 * 1024;
    } else {
        # size is in GB
        $sizeInBytes = $size * 1024 * 1024 * 1024;
    }
    my $sizeInBlocks = int($sizeInBytes / $blockSize);
    return $sizeInBlocks;
}

my ($logicalSize, $blockSize, $chunkSize, $partCount, $maxNameLen, %parts);

sub loadPartInfo()
{
    ($logicalSize, $blockSize, $chunkSize, $partCount, $maxNameLen, %parts) = getLWVMInfo();
}
loadPartInfo();

sub printPartitionLine($$$)
{
    my ($part, $lens, $fields) = @_;
    
    print "   ";
    foreach my $field (@$fields) {
        my $len = $lens->{$field};
        printf "%${len}s  ", $part->{$field};
    }
    print "\n";
}

sub printPartitions
{
    my $logHum = humanSize($logicalSize);
    print "   Logical size $logHum ($logicalSize), Block size $blockSize, chunk size $chunkSize\n";
    print "   Partition map:\n";
    
    my @fields = qw( name size byteSize );
    my %fieldLen = map { $_ => length($_) } @fields;
    
    foreach my $partId (keys(%parts)) {
        my $part = $parts{$partId};
        foreach my $field (@fields) {
            my $len = length($part->{$field});
            if ($len > $fieldLen{$field}) { $fieldLen{$field} = $len; }
        }
    }

    my %header = map { $_ => $_ } @fields;
    printPartitionLine(\%header, \%fieldLen, \@fields);
    my %sep = map { $_ => "-"x$fieldLen{$_} } @fields;
    printPartitionLine(\%sep, \%fieldLen, \@fields);
    
    foreach my $partId (keys(%parts)) {
        printPartitionLine($parts{$partId}, \%fieldLen, \@fields);
    }

    print "\n";
    system("df -h");
    print "\n";
}

sub adjustPart($$)
{
    my ($part, $adjust) = @_;
    
    my $str = ($adjust < 0) ? "Shrinking" : "Growing";
    
    my $curBlockSize = $part->{"blockSize"};
    my $newBlockSize = $curBlockSize + $adjust;
    
    my $curHumSize = humanSize($curBlockSize * $blockSize);
    my $newHumSize = humanSize($newBlockSize * $blockSize);
    
    print "$str $part->{name} from $curHumSize ($curBlockSize blocks) to $newHumSize ($newBlockSize blocks)\n\n";
    my @output = `lwvm adjust $part->{partNum} $newBlockSize 2>&1`;
    my $ret = $?;
    @output = map { "   $_" } @output;
    print join("", @output) . "\n";
    if ($?) {
        die "can't adjust $part->{name} partition\n";
    }
}

sub usage
{
    my $base = $0;
    $base =~ s|.*/||;
    print "\nUsage:\n";
    print "   $base <partition name> <desired size of partition>\n";
    print "      Change the indicated partition to the specified size\n";
    print "\n";
    print "   $base <partition name> -<size adjustment>\n";
    print "      Shrink the indicated partition by the specified size\n";
    print "\n";
    print "   $base <partition name> +<size adjustment>\n";
    print "      Grow the indicated partition by the specified size\n";
    print "\n";
    print "   When shrinking or growing the Data partition, space will be added to/taken from the System partition.\n";
    print "   When shrinking or growing any other partition, space will be added to/taken from the Data partition.\n";
    print "\n";
    print "   Sizes may be specified as:\n";
    print "      123b = 123 bytes\n";
    print "      123k = 123 KiB (123*1024 bytes)\n";
    print "      123m = 123 MiB (123*1024*1024 bytes)\n";
    print "      123g = 123 GiB (123*1024*1024*1024 bytes)\n";
    print "   With no suffix, the size is assumed to be in GiB.\n";
    print "\n";
    printPartitions();
    exit 1;
}

if ($#ARGV != 1) {
    usage();
}

if ($< != 0) {
    print "Must be run as root\n";
    exit 1;
}

my ($partition, $size) = @ARGV;
my $partLC = lc($partition);

my $targetPart = $parts{$partLC};
if (!defined($targetPart)) {
    print "Unknown target partition $partition\n\n";
    usage();
}

my $otherPartName = ($partLC eq "data") ? "system" : "data";

my $otherPart = $parts{$otherPartName};
if (!defined($otherPart)) {
    print "Couldn't find $otherPartName partition\n\n";
    usage();
}

my $adjust = undef;
if ($size =~ m|^([-+])(.*)$|) {
    ($adjust, $size) = ($1, $2);
}

my $curTargetBlockSize = $targetPart->{"blockSize"};
my $desiredTargetBlockSize = sizeInBlocks($size, $blockSize);

if ($adjust eq "-") {
    $desiredTargetBlockSize = $curTargetBlockSize - $desiredTargetBlockSize;
} elsif ($adjust eq "+") {
    $desiredTargetBlockSize = $curTargetBlockSize + $desiredTargetBlockSize;
}

my $diffBlocks = $desiredTargetBlockSize - $curTargetBlockSize;
my ($shrinkPart, $growPart);

if ($diffBlocks == 0) {
    print "$targetPart->{name} partition is already the desired size\n";
    exit 0;
}

print "Before adjustment:\n\n";
printPartitions();

system("/sbin/mount -uw /") && die "can't remount root partition\n";

if ($diffBlocks > 0) {
    adjustPart($otherPart, -$diffBlocks);
    adjustPart($targetPart, $diffBlocks);
} else {
    adjustPart($targetPart, $diffBlocks);
    adjustPart($otherPart, -$diffBlocks);
}

print "After adjustment:\n\n";
loadPartInfo();
printPartitions();
