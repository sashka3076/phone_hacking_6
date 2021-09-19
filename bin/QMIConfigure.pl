#!/usr/bin/perl


# Copyright Apple Inc. 2010
#
# For questions email Arjuna

use strict;

my $NVItemID = 6873;

sub printSetUsage
{
    printf( "Usage:\n" );
    printf( "\tperl <scriptName.pl> N port1QMIMapping port1DataMapping port2QMIMapping port2DataMapping ... portNQMIMapping portNDataMapping\n" );
    printf( "\nMappings can be:\n" );
    printf( "\tnone\n" );
    printf( "\tusb\n" );
    printf( "\tmux1\n" );
    printf( "\tmux2\n" );
    printf( "\tmux3\n" );
    printf( "\t...\n" );
    printf( "\tmuxMax\n" );

    printf( "\t\nNOTE: Note that Mux ports are interpreted in pairs on the BB side. mux1 = DLCI 1 and DLCI 2,  mux2 = DLCI 3 and DLCI 4 and so on\n" );

    printf( "\n\nExample:\n" );
    printf( "\tTo configure 2 QMI instances, first with both QMI and data mapped to usb, and then the second mapped to mux1:\n" );
    printf( "\tperl <scriptName.pl> 2 usb usb mux1 mux1\n" );
}

my $numArgs = $#ARGV + 1;
my @args = @ARGV;

if ( $numArgs < 2 )
{
    printSetUsage;
}
else
{
    my $numPorts = $args[0];
    printf( "Configuring For %u Ports\n", $numPorts );

    if ( $numPorts > 5 )
    {
        printf( "Too many ports %u\n", $numPorts );
        exit;
    }

    if ( $numArgs < $numPorts * 2 + 1 )
    {
        printSetUsage;
    }
    else
    {
        my $commandPayload = sprintf( "%02x ", $numPorts );;

        my $i;
        foreach $i ( 1 .. $numArgs - 1 )
        {
            my $p       = $args[$i];
            my $portID;
            my $extra;

            if ( $p eq "usb" )
            {
                $portID = 0x200;
                $extra = "USB";
            } 
            elsif ( $p eq "none" )
            {
                $portID = 0;
                $extra = "NONE";
            }
            elsif ( $p =~ m/^mux/ )
            {
                $p =~ s/mux//;

                my $dlci;
                $dlci = $p * 2;
                if ( $i % 2 == 1 )
                {
                    $dlci--;
                }

                $portID = 0x2FF + $p;
                $extra = sprintf( "AP DLCI %u", $dlci );
            }
            else
            {
                printf( "Unrecognized port\n" );
                exit;
            }
            
            my $QMIOrData;
            my $qmi = ( $i - 1 ) / 2;

            $commandPayload .= sprintf( "%02x %02x ", ( $portID & 0xFF ), ( $portID >> 8 ) );
            if ( $i % 2 == 1 )
            {
                $QMIOrData = "QMI";
                $commandPayload .= sprintf( "01 00 01 00 ", $portID );
            }
            else
            {
                $QMIOrData = "Data";
            }

            printf( "QMI Instance %u: %s: Using Port ID 0x%x \t-- $extra\n", $qmi, $QMIOrData, $portID, $extra );
        }

        printf( "Command: %s\n", $commandPayload );

        my $cmd = sprintf( "ETLTool nvwrite $NVItemID $commandPayload\n" );
	system( $cmd );
    }
}

