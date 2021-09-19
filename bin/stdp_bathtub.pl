#!/usr/bin/perl
#This perl script runs the bathtub test routines on B82/B92 on an actual iproduct.
#Last updated: 2011-04-21
#
# Changelog:
# Rev0.3 -
#   1) Corrected eyecenter calculation algorithm
#   2) Almost total rewrite for b82/b92
#   3) Temporarily removed continuous test mode and GSM power sweep mode (pending major rewrite...)
# Rev0.4 -
#   1) Split out bathtub script to run each lane side-by-side
# Rev0.5 -
#   1) Formatting fix by intern Daniel
# Rev0.6 -
#   1) Changed delay to readback EQ and CPtrim from 10ms to 100ms.
# Rev0.7 -
#   1) Changed to new method of bathtub test to add polling according to these instructions from ST:
#     a. Write DPCD 0x560 to 0xE1
#     b. Wait until DPCD 0x560 change to 0xE2
#     c. Program 0x30B to 0x30F and write DPCD 0x560 to 0xEE to start testing. (same as old one)
#     d. After testing, write DPCD 0x560 to 0xE0
#     e. wait until DPCD 0x560 change to 0
# Rev0.8 -
#   1) Don't leave test mode after each leg of the bathtub test (i.e. don't write 0x560 to 0xE0)
# Rev0.9 -
#   1) Added note at end of message indicating what data to copy into the log spreadsheet for WGT
#   2) Added "killall iapd" to the end of the script to simulate dongle disconnect/reconnect
# Rev1.0 -
#   1) Added vertical eyesize reporting metric
# Rev1.1 -
#   1) Added reference for another processor

#Globals
$Version = "1.0";
@drivelevel;

use Time::HiRes qw( usleep);
use Getopt::Long qw( GetOptions);

#subroutines
sub dpcd_read_raw($$);
sub dpcd_read($$);
sub dpcd_write($$$);
sub SortEye;
sub RunBert;
sub Bert;
sub StatusReport;
sub ReadEQ;
sub ReadLC;
sub ReadCPTrim;
sub DPstatus;
sub reg_read;
sub printq;

#Command line options
my $period = 20; #10->period
my $unit = 0;    #period unit (0->1ms, 1->10ms, 2->100ms per period)
my $config = "DEFAULT";   #Configuration Name
my $bert = 0      ;      #Run a bit error rate test for $bert seconds
my $quiet = 0;           #Quiet output. Just output one line of bathtub test
my $dontreset = 0;       #Don't reset at the end of the script
my $showhelp = 0;     #Show help

$GetOptions = GetOptions (
                          "p=i" => \$period,
                          "u=i" => \$unit,
                          "d=s" => \$config,
                          "b=i" => \$bert,
                          "q" =>   \$quiet,
                          "d" =>   \$dontreset,
                          "h" =>   \$showhelp);

if($showhelp) {
my $helpmessage = <<"EOF";
Usage:
./stdp_bathtub [options]

Options [default]:
   -p i -> test period in units [10]
   -u i -> period units (0->1ms, 1->10ms, 2->100ms per period, etc) [0]
   -d s -> Tag data with a configuration name.  (Makes it easy to grep the results) [DEFAULT]
   -b i -> Run a BERT test for i seconds at default trained link settings
   -d   -> Don't reset (killall iapd) at the end of the script 
   -h   -> Show help (this message) and exit
EOF
   print "STDP Bathtub script version: $Version\n";
   print $helpmessage;
   exit(0);
}

#Print video status
system("displayPort -cl");

#First, identify iProduct and processor:
$uname = `uname -a`;
printq "System: $uname";
if( $uname =~ /S5L8930X/ ) {
   printq "Processor: H3\n";
   $base = "0x84900";
}
elsif( $uname =~ /S5L8940X/ ) {
   printq "Processor: H4P\n";
   $base = "0x39700";
}
elsif( $uname =~ /S5L8945X/ ) {
   printq "Processor: H4G\n";
   $base = "0x39700";
}
elsif( $uname =~ /S5L8942X/ ) {
   printq "Processor: H4A\n";
   $base = "0x39700";
}
else {
   die "Unknown processor type.\n";
}

printq "Bathtub script version: $Version\n";

#First, determine product from DPCD Branch device ID register and set bathtub registers accordingly
@ID = dpcd_read('0x503','9');
if (($ID[0] == '70')&&($ID[1] == '56')&&($ID[2] == '47')&&($ID[3] == '41')&&($ID[4] == '62')&&($ID[5] == '00')) {
   printq "Product Found: B92\n";
   $maxlanecount   = 2;
   $reg_lanetest   = '0x30B';        #Lane under test
   $reg_patttype   = '0x30C';        #Pattern Type (0->Normal data, 1->PRBS7)
   $reg_timeunit   = '0x30D';        #Time unit (0=1ms, 1=10ms, 2=100ms)
   $reg_timeperiod = '0x30E';        #Time period (x * Time unit)
   $reg_forceEQ    = '0x30F';        #EQ Value to test
   $run_bathtub_poll = 1;       #Joe's new polling command to start/stop bathtub test
   @bathtub_cmd    = ('0x560','0xEE','0x564');  #CommandReg, Command, ResultReg
   @EQread_cmd     = ('0x560','0xAA','0x30B');  #CommandReg, Command, ResultReg
   @CPread_cmd     = ('0x560','0xCC','0x30B');  #CommandReg, Command, ResultReg
#   @EQread_cmd     = ('0x560','0xCC','0x30B');  #CommandReg, Command, ResultReg
#   @CPread_cmd     = ('0x560','0xAA','0x30B');  #CommandReg, Command, ResultReg
} 
elsif (($ID[0] == '70')&&($ID[1] == '48')&&($ID[2] == '44')&&($ID[3] == '4d')&&($ID[4] == '49')&&($ID[5] == '64')) {
   printq "Product Found: B82\n";
   $maxlanecount   = 2;
   $reg_lanetest   = '0x30B';   #Lane under test
   $reg_patttype   = '0x30C';   #Pattern Type (0->Normal data, 1->PRBS7)
   $reg_timeunit   = '0x30D';   #Time unit (0=1ms, 1=10ms, 2=100ms)
   $reg_timeperiod = '0x30E';   #Time period (x * Time unit)
   $reg_forceEQ    = '0x30F';   #EQ Value to test
   $run_bathtub_poll = 1;       #Joe's new polling command to start/stop bathtub test
   @bathtub_cmd    = ('0x560','0xEE','0x564');  #CommandReg, Command, ResultReg
   @EQread_cmd     = ('0x560','0xAA','0x30B');  #CommandReg, Command, ResultReg
   @CPread_cmd     = ('0x560','0xCC','0x30B');  #CommandReg, Command, ResultReg
#   @EQread_cmd     = ('0x560','0xCC','0x30B');  #CommandReg, Command, ResultReg
#   @CPread_cmd     = ('0x560','0xAA','0x30B');  #CommandReg, Command, ResultReg
} 
elsif (($ID[6] == '56')&&($ID[7] == '02')&&($ID[8] == '03')) {
   printq "Product Found: B56\n";
   $maxlanecount   = 2;
   $reg_lanetest   = '0x301';   #Lane under test
   $reg_patttype   = '0x302';   #Pattern Type (0->Normal data, 1->PRBS7)
   $reg_timeunit   = '0x305';   #Time unit (0=1ms, 1=10ms, 2=100ms)
   $reg_timeperiod = '0x304';   #Time period (x * Time unit)
   $reg_forceEQ    = '0x303';   #EQ Value to test
   $run_bathtub_poll = 0;       #Don't run Joe's new polling command to start/stop bathtub test
   @bathtub_cmd    = ('0x300','0xEE','0x500');  #CommandReg, Command, ResultReg
   @EQread_cmd     = ('0x300','0xAA','0x500');  #CommandReg, Command, ResultReg
   @CPread_cmd     = ('0x300','0xCC','0x500');  #CommandReg, Command, ResultReg
} 
else {
   die "DP Sink not recognized for bathtub test script.\n";
} 

@actualeq = ReadEQ;
@actualcp = ReadCPTrim;
$actualVtune = reg_read(0x380);
$currentVtune = hex($actualVtune);
($linkrate,$lanecount) = dpcd_read('0x100',2);
$lanecount = ($lanecount & 0x0007);
printq "LINKRATE: $linkrate\n";
printq "LANECOUNT: $lanecount\n";
printq "VTUNE: $actualVtune\n";

StatusReport;
DPstatus;

printq "\nRunning Bathtub with EQ sweep:\n";
for($lane=0; $lane<$lanecount ; $lane++) {
   $eyesize_summary[$lane] = "EQSWEEP_EYESIZE_L$lane: ";
   $eyecenter_summary[$lane] = "EQSWEEP_EYECENTER_L$lane: ";
   $eyesize_summary[$lane] .= $config;
   $eyecenter_summary[$lane] .= $config;
   $eyesize_vertical[$lane] = 0;
}
RunPrintBathtub('EQ',0,0);
RunPrintBathtub('EQ',1,1);
RunPrintBathtub('EQ',2,2);
RunPrintBathtub('EQ',3,3);
RunPrintBathtub('EQ',4,4);
RunPrintBathtub('EQ',5,5);
RunPrintBathtub('EQ',6,6);
RunPrintBathtub('EQ',7,7);
for($lane=0; $lane<$lanecount ; $lane++) {
   print "$eyesize_summary[$lane]\n";
   print "$eyecenter_summary[$lane]\n";
   $QARESULT[$lane] = "QARESULT_L$lane:\t$eyesize_actual[$lane]\t$eyesize_vertical[$lane]\t$drivelevel[$lane]\t$linkrate\t$actualeq[$lane]\t$actualVtune\n";
}

printq "\nRunning Bathtub with VTune sweep:\n";
for($lane=0; $lane<$lanecount ; $lane++) {
   $eyesize_summary[$lane] = "VTSWEEP_EYESIZE_L$lane: ";
   $eyecenter_summary[$lane] = "VTSWEEP_EYECENTER_L$lane: ";
   $eyesize_summary[$lane] .= $config;
   $eyecenter_summary[$lane] .= $config;
   $eyesize_vertical[$lane] = 0;
}
reg_write(0x380,0x77);
RunPrintBathtub('VT',@actualeq);
reg_write(0x380,0x66);
RunPrintBathtub('VT',@actualeq);
reg_write(0x380,0x55);
RunPrintBathtub('VT',@actualeq);
reg_write(0x380,0x44);
RunPrintBathtub('VT',@actualeq);
reg_write(0x380,0x33);
RunPrintBathtub('VT',@actualeq);
reg_write(0x380,0x22);
RunPrintBathtub('VT',@actualeq);
reg_write(0x380,0x11);
RunPrintBathtub('VT',@actualeq);
reg_write(0x380,0x00);
RunPrintBathtub('VT',@actualeq);
for($lane=0; $lane<$lanecount ; $lane++) {
   print "$eyesize_summary[$lane]\n";
   print "$eyecenter_summary[$lane]\n";
}

printq "\nReturning VTune back to original value of $actualVtune.\n";
reg_write(0x380,hex($actualVtune));

if(!$dontreset) {
   printq "\nResetting dongle by running \"killall iapd\"...\n";
   system("killall iapd");
}

print "Results for QA spreadsheet summary:\n";
print "QARESULT_Lx:\tEyesize\tVrtsize\tHxDrive\tRate\tRxEQ\tVtune\n";
for($lane=0; $lane<$lanecount ; $lane++) {
   print $QARESULT[$lane];
}


exit(0);

#################################################################
#   Subroutines 
#################################################################


sub StatusReport {
   printq "Current state of reg 0x000-0x020:\n";
   $results = dpcd_read_raw('0x0','32');
   printq "$results\n";

   printq "Current state of reg 0x100-0x120:\n";
   $results = dpcd_read_raw('0x100','32');
   printq "$results\n";

   printq "Current state of reg 0x200-0x220:\n";
   $results = dpcd_read_raw('0x200','32');
   printq "$results\n";

   printq "ST's HW rev:\n";
   $results = dpcd_read_raw('0x509','1');
   printq "$results\n";

   printq "ST's FW rev:\n";
   $results = dpcd_read_raw('0x50A','2');
   printq "$results\n";

   printq "Current state of EQ:\n";
   for($lane=0; $lane<$maxlanecount ; $lane++) {
      printq "EQ Lane $lane: $actualeq[$lane]\n";
   }
   printq "\n";

   printq "Current state of CPTrim:\n";
   for($lane=0; $lane<$maxlanecount ; $lane++) {
      printq "CPTrim Lane $lane: $actualcp[$lane]\n";
   }
   printq "\n";
}

sub ReadEQ {
   dpcd_write($EQread_cmd[0],1,$EQread_cmd[1]);
   usleep(200000);
   my @EQRead = dpcd_read($EQread_cmd[2],$maxlanecount);
   for($i=0;$i<$maxlanecount;$i++) {
      $EQRead[$i] = hex($EQRead[$i]);
   }
   return @EQRead;
}

sub ReadCPTrim {
   dpcd_write($CPread_cmd[0],1,$CPread_cmd[1]);
   usleep(200000);
   my @CPTrim = dpcd_read($CPread_cmd[2],$maxlanecount);
   for($i=0;$i<$maxlanecount;$i++) {
      $CPTrim[$i] = hex($CPTrim[$i]);
   }
   return @CPTrim;
}

sub RunPrintBathtub ($@) {
   my $testname = shift;
   my @EQ;
   for($lane=0; $lane<$lanecount ; $lane++) {
      $EQ[$lane] = shift;
   }

   my $eyedata, $eyesize, $eyecenter;
   my $time = (10**$unit)*$period;

#update global currentVtune
   $currentVtune = hex(reg_read(0x380));

   printf ("BT$testname: $config VSWING%2.2x $time ",$currentVtune);
   for($lane=0; $lane<$lanecount ; $lane++) {
      ($eyedata,$eyesize,$eyecenter) = SingleBathtub($lane,$EQ[$lane]);
      printf ("LN$lane-EQ$EQ[$lane] $eyedata %2d %2.1f ",$eyesize, $eyecenter);
      $eyesize_summary[$lane] .= " $eyesize";
      $eyecenter_summary[$lane] .= " $eyecenter";
      if($eyesize>0) {
         $eyesize_vertical[$lane]++;
      }
      if(($currentVtune == hex($actualVtune))&&($EQ[$lane] == $actualeq[$lane])) {
         $eyesize_actual[$lane] = $eyesize;
         $eyecenter_actual[$lane] = $eyecenter;
      }
   }
   print "\n";
} 

sub SingleBathtub ($$) {
   my $lane = shift;
   my $EQ = shift;
   my $periodh = sprintf("0x%x",$period);
   my $unith = sprintf("0x%x",$unit);

   if($run_bathtub_poll) {
      dpcd_write('0x560',1,'0xE1');
      my $timeout = 100;
      while(($timeout--)>0) {
         if($timeout==0) {
            die "\nPretest: timeout waiting for reg 0x560 to change from 0xE1 to 0xE2\n";
         }
         usleep(20000);
         my @data = dpcd_read('0x560',1);
#print "CHECK: $data[0]\n";
         if($data[0] =~ /e2/) {
            $timeout = 0;
         }
      }
   }

   dpcd_write($reg_lanetest,1,$lane);
   dpcd_write($reg_forceEQ,1,$EQ);
   dpcd_write($reg_patttype,1,'0x00');
   dpcd_write($reg_timeunit,1,$unith);
   dpcd_write($reg_timeperiod,1,$periodh);


   dpcd_write($bathtub_cmd[0],1,$bathtub_cmd[1]);
   $sleep = (1000*(10**$unit)*$period*64 + 100000);
   usleep($sleep);
   if($run_bathtub_poll) {
      my $timeout = 100;
      while(($timeout--)>0) {
         if($timeout==0) {
            die "\nEndtest: timeout waiting for reg 0x56C to change from 0x00 to 0x01\n";
         }
         usleep(20000);
         my @data = dpcd_read('0x56C',1);
#print "CHECK2: $data[0]\n";
         if($data[0] =~ /01/) {
            $timeout = 0;
         }
      }
   }

   my @btresult = dpcd_read($bathtub_cmd[2],9);
#Convert to format that the SortEye subroutine understands (comma separated, decimal form)
   my $rawdata = "";
   for($i=0;$i<9;$i++) {
      $rawdata .= ",";
      $rawdata .= hex($btresult[$i]);
   }
   $eyeoutput = "";

   if($run_bathtub_poll) {
#      dpcd_write('0x560',1,'0xE0');
      my $timeout = 100;
      while(($timeout--)>0) {
         if($timeout==0) {
            die "\nPosttest: timeout waiting for reg 0x560 to change from 0xE0 to 0x00\n";
         }
         usleep(20000);
         my @data = dpcd_read('0x560',1);
#print "CHECK2: $data[0]\n";
         if($data[0] =~ /00/) {
            $timeout = 0;
         }
      }
   }

    return SortEye($rawdata, $EQ, $lane);
}


sub dpcd_read_raw($$) {
   my $addr = shift;
   my $length = shift;
   return `displayPort -rdpcd $addr $length`;
}

sub dpcd_read($$) {
   my $addr = shift;
   my $length = shift;
   my $data = `displayPort -rdpcd $addr $length`;
   chomp($data);
#print "$addr $length $data\n";
   my @datas, @datas2;
   (undef, @datas, undef) = split(/\s+/,$data,$length+1);
#   for($i=0;$i<$length; $i++) {
#      $datas2[$i] = hex($datas[$i]);
#   }
   return @datas;
}

sub dpcd_write($$$) {
   my $addr = shift;
   my $length = shift;
   my $data = shift;
   return `displayPort -wdpcd $addr $length $data`;
}

sub RunBert {
   printq "Running BERT test for $bert seconds\n";
   @bertcnt = Bert();
   print "BERTPRETEST: $config 0 $bertcnt[0] $bertcnt[1]\n";
   sleep($bert);
   @bertcnt = Bert();
   print "BERTTEST: $config $bert $bertcnt[0] $bertcnt[1]\n\n";
}

sub Bert {
   $results = dpcd_read_raw('0x210','4');
   my @bertlane0;
   my @bertlane1;
   my @bertcnt;
   (undef, $bertlane0[0], $bertlane0[1], $bertlane1[0], $bertlane1[1]) = split(/\s+/,$results,5);
   $bertlane0[1] = hex($bertlane0[1]);
   $bertlane0[0] = hex($bertlane0[0]);
   $bertlane1[1] = hex($bertlane1[1]);
   $bertlane1[0] = hex($bertlane1[0]);
   $bertcnt[0] = $bertlane0[1]*256 + $bertlane0[0] - 32768;
   $bertcnt[1] = $bertlane1[1]*256 + $bertlane1[0] - 32768;
#   print "Start Error count: $bertlane0[1], $bertlane0[0], $bertlane1[1], $bertlane1[0]\n";
   return @bertcnt;
}

sub SortEye ($$$) {
#This routine is similar to what is used on the B56 production line
   my $rawdata = shift;
   my $currenteq = shift;
   my $currentlane = shift;
   my $done;
   my @data;
   my @eye;
   my $eyeoutput;
  
   (undef,@data) = split(/\,/,$rawdata,10); #split out the raw data
   $done = pop(@data);  #pop off the done bit

   if(!$done) {
      return ("----------------------------------------------------------------",-1,-1);  #Return -100,-100 if the done bit wasn't set
   }

   for($i=0;$i<8;$i++) {
      for($j=0;$j<8;$j++) {
         $mask = 1 << $j;
         $idx = ($i << 3) + $j;
         if($mask & $data[$i]) {
            $eyeoutput .= (($currentVtune == hex($actualVtune))&&($currenteq == $actualeq[$currentlane])&&($idx == $actualcp[$currentlane])) ? "X" : "1";
            $eye[$idx] = 1;
         }
         else {
            $eyeoutput .= (($currentVtune == hex($actualVtune))&&($currenteq == $actualeq[$currentlane])&&($idx == $actualcp[$currentlane])) ? "." : "0";
            $eye[$idx] = 0;
         }
      }
   }

   #First, find the center of the eye, starting at 32.
   my $eye_center_not_found = 1;
   my $eye_center_test = 32;
   my $eye_offset_test = 1;
   my $eye_offset_dir = 1;
   while($eye_center_not_found) {
      if($eye[$eye_center_test] == 0) {
         $eye_center_not_found = 0;
      }
      else {
         if($eye_offset_dir) {
            $eye_center_test = 32 - $eye_offset_test;
            $eye_offset_dir = 0;
         }
         else {
            $eye_center_test = 32 + $eye_offset_test;
            $eye_offset_dir = 1;
            $eye_offset_test++;
         }
      }
      if($eye_center_test == 0) {
         $eye_center_test = -1; 
         return ($eyeoutput,0,-1);
         $eye_center_not_found = 0;
      }
#print "$eye_center_test, ";
   }

  
   #Now, find the eye, starting in the center and counting up.
   my $eyesizep = 0;
   my $noerrors = 1;
   for($i=$eye_center_test;$i<64;$i++) {
      if($noerrors && (!$eye[$i])) {
         $eyesizep++;
      }
      else {
         $noerrors = 0;
      }
   }

   #Now, start in the center, and count down.
   my $eyesizen = 0;
   $noerrors = 1;
   for($i=($eye_center_test-1);$i>-1;$i--) {
      if($noerrors && (!$eye[$i])) {
         $eyesizen++;
      }
      else {
         $noerrors = 0;
      }
   }

   my $eyesize = $eyesizep + $eyesizen;

   my $eyecenter = $eye_center_test + ($eyesizep - $eyesizen)/2 - 1/2;
   #print "SIZE: $eyesizep $eyesizen $eyesize $eyecenter \n";

   return ($eyeoutput,$eyesize,$eyecenter);
}

sub DPstatus {
   if(!$quiet) {
      print "HxStatus: Critical Registers in DP-TX blocki, assuming base ${base}xxx\n";
      my $data = reg_read(0x370);
      print "Reg370: $data #TX Term[5:4]:(01->50ohm, 11->45ohm), Vboost[3]:(1->30%), all other bits should be 0.\n";

      $data = reg_read(0x380);
      print "Reg380: $data #LANE1_Vswing_tune[6:4], LANE0_Vswing_tune[2:0]\n";

      $data = reg_read(0x680);
      print "Reg680: $data #LINK_BW_SET[3:0]\n";

      $data = reg_read(0x684);
      print "Reg684: $data #LANE_COUNT_SET[2:0]\n";

      $data = reg_read(0x688);
      print "Reg688: $data #Scrambling[5]:(1->OFF, 0->ON), LinkQualPattern[3:2]:(11->PRBS7)\n";

      $drivelevel[0] = reg_read(0x68C);
      print "Reg68C: $drivelevel[0] #LANE0:  MAX_PRE_REACHED[5],PREEMPHASIS[4:3],MAX_DRIVE_REACHED[2],DRIVE_CURRENT[1:0]\n";

      $drivelevel[1] = reg_read(0x690);
      print "Reg690: $drivelevel[1] #LANE1:  MAX_PRE_REACHED[5],PREEMPHASIS[4:3],MAX_DRIVE_REACHED[2],DRIVE_CURRENT[1:0]\n";
   }
}

sub reg_read($) {
   my $reg = shift;
   my $reg2 = sprintf("%s%3.3x",$base,$reg);
   my $data = `reg read memory:$reg2`;
   (undef,$data) = split(/\n/,$data,2);
   (undef,undef,undef,$data,undef) = split(/\s+/,$data,5);
   return($data);
}

sub reg_write($$) {
   my $reg = shift;
   my $data = shift;
   my $reg2 = sprintf("%s%3.3x",$base,$reg);
   my $data2 = sprintf("%2.2x",$data);
   `reg write memory:$reg2,2=0x$data2`;
}

sub printq ($) {
   my $data = shift;
   if(!$quiet) {
      print("$data");
   }
}
