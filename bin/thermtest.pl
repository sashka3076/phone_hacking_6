#!/usr/bin/perl

use strict;
use warnings;

# ------------- product-specific truth references and test parameters below --------------

my %slow_die_loop_test_params_table = (
    "S5L8960X" => { 
        cpu_virus_name    => "thermalCycloneSynthetic",
        die_temp_4CCs     => "TC0s",
        target_temp       => 75,
    },
    "T7000" => { 
        cpu_virus_name    => "thermalTyphoonSynthetic",
        die_temp_4CCs     => "Tc1a",
        target_temp       => 80,
    },
    "T7001" => {
        cpu_virus_name    => "thermalTyphoonSynthetic",
        die_temp_4CCs     => "Tc1a",
        target_temp       => 80,
    },
    "S8000" => {
        cpu_virus_name    => "thermalTwisterSynthetic",
        die_temp_4CCs     => "Tc1a",
        target_temp       => 80,
    },
    "S8001" => {
        cpu_virus_name    => "thermalTwisterSynthetic",
        die_temp_4CCs     => "Tc1a",
        target_temp       => 85,
    },
    "S8003" => {
        cpu_virus_name    => "thermalTwisterSynthetic",
        die_temp_4CCs     => "Tc1a",
        target_temp       => 80,
    }
);

my %skin_models_by_product = (
    "J1"   => [ "TSBH" ],
    "J2"   => [ "TSBR", "TSBH" ],
    "J2a"  => [ "TSBR", "TSBH" ],
    "J33"  => [ "TSBN", "TSBC", "TSBP" ],
    "J33i" => [ "TSBN", "TSBC", "TSBP" ],
    "J42d" => [ "TSLE" ],
    "J71"  => [ "TS0H" ],
    "J72"  => [ "TS0H", "TSBR" ],
    "J73"  => [ "TS0H", "TSBR" ],
    "J81"  => [ "TSBH" ],
    "J82"  => [ "TSBH", "TSBR" ],
    "J85"  => [ "TS0H" ],
    "J85m" => [ "TS0H" ],
    "J86"  => [ "TS0H", "TSBR" ],
    "J86m" => [ "TS0H", "TSBR" ],
    "J87"  => [ "TS0H", "TSBR" ],
    "J87m" => [ "TS0H", "TSBR" ],
    "J96"  => [ "TSBH" ],
    "J97"  => [ "TSBH", "TSBR" ],
    "K93a" => [ "TSBH" ],
    "N102" => [ "TS0D", "TSBH" ],
    "N27a" => [ "TSBH", "TScH", "TSdH", "TSFD" ],
    "N28a" => [ "TSBH", "TScH", "TSdH", "TSFD" ],
    "N41"  => [ "TSBR", "TSBH", "TSFC" ],
    "N42"  => [ "TSBR", "TSBH", "TSFC" ],
    "N48"  => [ "TSFX", "TSFH", "TSFC" ],
    "N49"  => [ "TSFX", "TSFH", "TSFC" ],
    "N51"  => [ "TSBR", "TSBH", "TSFC" ],
    "N53"  => [ "TSBR", "TSBH", "TSFC" ],
    "N56"  => [ "TSFL", "TSBH", "TSBL", "TSBR", "TSFC" ],
    "N61"  => [ "TSFL", "TSBH", "TSBL", "TSBR", "TSFC" ],
    "N66"  => [ "TSFH", "TSFL", "TSFD", "TSBH", "TSBL", "TSBR", "TSFC" ],
    "N66m" => [ "TSFH", "TSFL", "TSFD", "TSBH", "TSBL", "TSBR", "TSFC" ],
    "N71"  => [ "TSFH", "TSFL", "TSFD", "TSBH", "TSBL", "TSBR", "TSFC" ],
    "N71m" => [ "TSFH", "TSFL", "TSFD", "TSBH", "TSBL", "TSBR", "TSFC" ],
    "N78"  => [ "TS0C", "TS0D", "TS0H" ],
    "P101" => [ "TS0H" ],
    "P102" => [ "TS0H", "TSBR" ],
    "P103" => [ "TS0H", "TSBR" ],
    "P105" => [ "TSBH" ],
    "P106" => [ "TSBH", "TSBR" ],
    "P107" => [ "TSBH", "TSBR" ],
);

my @products_using_lifetime_servo = ("J81", "J82", "J96", "J97", "N61", "N56");

# ------------- main test set below --------------

my $soc_name = get_soc_name();
my $product_name = get_product_name();

# Turn on ThermalMonitor logging, kill UserEventAgent so that it loads again, then sleep for 30 seconds
# to get all the possible initial error logging into the log file
my $LOG_FILE = "/var/log/ThermalMonitor_thermtest.log";
system("rm -f $LOG_FILE");
send_thermtune_command("--logfile $LOG_FILE");
system("killall -9 UserEventAgent");
system("sleep 30");

# Start collecting a tGraph file with temperature test results
my $TGRAPH_FILE = "/var/log/ThermalMonitor_thermtest.tgraph.csv";
send_thermtune_command("--notGraphLogFile");
send_thermtune_command("--forceSkipInfoOnlySensors on");
system("rm -f $TGRAPH_FILE");
send_thermtune_command("--tGraphLogFile $TGRAPH_FILE");
send_thermtune_command("--writeTestKey 0");

# ... and start actually testing
print("[TEST] thermtest $product_name $soc_name\n");
$product_name =~ s/AP//g;

test_always_pass();

if ($slow_die_loop_test_params_table{$soc_name}) {
    my %params = %{$slow_die_loop_test_params_table{$soc_name}};        # TODO: this section looks a bit squirrely
    if (%params) {
        test_cpu_virus_control(%params);
    }
}

test_wdt();

my @skin_model_4CCs;
my $product_uses_lifetime_servo;
if ($skin_models_by_product{$product_name}) {
    @skin_model_4CCs = @{$skin_models_by_product{$product_name}};
    $product_uses_lifetime_servo = grep { /$product_name/ } @products_using_lifetime_servo;
    if (@skin_model_4CCs) {
        test_required_fields_valid();
    }
}

# Done with all tests
send_thermtune_command("--writeTestKey 0");
system("sleep 5");

# Check if there is any ThermalMonitor error message
check_log_error();

# Turn off ThermalMonitor logging, but leave the files around to be included in BATS test results
send_thermtune_command("--nologfile");
send_thermtune_command("--notGraphLogFile");


# ------------- individual test definitions below --------------

# Define one test that runs on all platforms and passes always.  This ensures that when run on products for 
# which no optional tests (e.g., SoC-based ones) are defined, the unit test still produces non-empty output.
# No idea whether I need this, but I'd rather see 1/1 tests pass than 0/0 (whatever that might mean).
sub test_always_pass {
    print("[BEGIN] test_always_pass\n");
    print("[PASS] always\n");
}

sub test_cpu_virus_control {
    my %args = (@_);    
    my $cpu_virus_name = $args{cpu_virus_name};
    my $die_temp_4CC = $args{die_temp_4CCs};        # TODO: handle multiple die temp sensors and do pass/fail on max value
    my $target_temp = $args{target_temp};
    my $max_start_temp = 50;                        # don't start test with an arbitrarily hot die (TODO: do we actually care?)
    my $min_transient_temp = $target_temp + 10;     # need some sort of decent transient to make the control test meaningful
    my $control_target_max_temp_error = 6;          # arbitrary--loop response may not be tuned well enough in all cases
    my $control_temp_lower_limit = $target_temp - $control_target_max_temp_error;
    my $control_temp_upper_limit = $target_temp + $control_target_max_temp_error;

    # Give die a chance to drop to normal temperature if it's hot from previous testing
    send_thermtune_command("--writeTestKey 1");
    system("sleep 30");

    print("[BEGIN] test_cpu_virus_control\n");
    
    my $die_temp = get_die_temp($die_temp_4CC);
    my $kDVD1 = get_kDVD1();
    if ($die_temp > $max_start_temp) {
        print("[FAIL] Invalid die temp for test start ($die_temp C, kDVD1 $kDVD1)\n");
        return; 
    } else {
        print("Valid die temp for test start ($die_temp C, kDVD1 $kDVD1)\n");
    }
    
    # Start the CPU thermal virus and allow for an initial temperature transient.  The transient should be 
    # managed by the fast die control loop and get the die up nice and hot.  Don't wait too long to confirm 
    # the transient response, though, or the slow loop will have a chance to spin up.  If the transient didn't
    # get well above the slow loop's die temp target, then we really aren't learning anything from the test
    # and the unexpected condition should be flagged as a failure.
    start_cpu_virus($cpu_virus_name);
    system("sleep 10");
    
    $die_temp = get_die_temp($die_temp_4CC);
    $kDVD1 = get_kDVD1();

    # Print out the measured transient info (Exepcted to be above target for most platforms,
    # but not exactly a test failure if it isn't)
    print("Info: 10 second die temp transient ($die_temp C, kDVD1 $kDVD1)\n");
    
    # Give the slow loop time to pull the die temp down to the long-term target and stabilize
    system("sleep 120");
    
    $die_temp = get_die_temp($die_temp_4CC);
    $kDVD1 = get_kDVD1();
    if ($die_temp > $control_temp_upper_limit) {
        print("[FAIL] Die temp uncontrolled ($die_temp C, kDVD1 $kDVD1)\n");
    } elsif($die_temp < $control_temp_lower_limit) {
        print("[FAIL] Die temp loop poorly tuned ($die_temp C, kDVD1 $kDVD1)\n");
    } else {
        print("[PASS] Die temp controlled ($die_temp C, kDVD1 $kDVD1)\n");
    }
    
    stop_cpu_virus($cpu_virus_name);
    system("sleep 10");
}

sub test_wdt
{
    print("[BEGIN] test_wdt\n");
    
    my $wdtlog = `sysctl -q -n debug.wdtlog`;
    if ($wdtlog eq "") {
        print "[PASS] sysctl unsupported\n";
    } else {
        my $test_passed = 0;
        chomp($wdtlog);
        my @tags = split(" ", $wdtlog);
        my @tags_u = grep(/u/, @tags);
        if (scalar(@tags_u)) {
            my $last_update = $tags_u[-1];
            my ($last_update_time, $last_update_code) = split("u", $last_update);
            if ($last_update_time == 0) {
                $test_passed = 1;
            }
        }
        print $test_passed == 1 ? "[PASS]" : "[FAIL]";
        print " $wdtlog\n";
    }
}

sub test_required_fields_valid
{
    print("[BEGIN] test_required_fields_valid\n");
    
    # Quiesce, and then wait for one more row in the tGraph CSV (which might take longer than one CLTM heartbeat if reduced-rate mode is active)
    send_thermtune_command("--writeTestKey 2");
    system("sleep 30");
    my $linecount_original = `cat $TGRAPH_FILE | wc -l`;
    my $linecount = $linecount_original;
    do {
        system("sleep 5");
        $linecount = `cat $TGRAPH_FILE | wc -l`;
    } while ($linecount == $linecount_original);
    my $csv = `cat $TGRAPH_FILE`;
    my @lines = split("\n", $csv);
    my @header_fields = split(",", $lines[0]);
    my @data_fields = split(",", $lines[-1]);
    
    my $failures_found = 0;
    my $idx = 0;
    
    for my $header_field (@header_fields) {
        trim_in($header_field);
        if (field_must_be_valid($header_field)) {
            my $check_value = $data_fields[$idx];
            trim_in($check_value);
            print "$header_field, $check_value";
            if (field_value_invalid($header_field, $check_value)) {
                print " *****";
                $failures_found = 1;
            }
            print "\n";
        }
        $idx++;
    }
    
    print $failures_found ? "[FAIL] some fields invalid\n" : "[PASS] all fields valid\n";
}

sub check_log_error {
    print("[BEGIN] check_log_error\n");
    my $errorlog = `grep -i error $LOG_FILE`;
    if ($errorlog eq "") {
        print "[PASS] No ThermalMonitor error\n";
    } else {
        print "[FAIL] ThermalMonitor errors found\n $errorlog\n";
    }
}

# ------------- helper subroutines below --------------

# Use the kern.version sysctl to infer (yes, somewhat unsafely) which SoC we're running on by looking at the 
# last field of the ".../DEVELOPMENT_ARM64_T7000" string and then use that determination to select SOC-specific 
# tests or parameters.  Which thermal viruses to run would be one such use.  We can also confirm that we're 
# doing the right thing for the specific case of the CPU thermal virus by looking at the hw.cpufamily sysctl, 
# which provides answers at the granularity of Cyclone, Typhoon, etc., though this is probably overkill.
sub get_soc_name {
    my $soc = "";
    my $kernel_version = `sysctl kern.version`;
    my $idx = rindex($kernel_version, "_");
    if ($idx != -1) {
        $soc = substr($kernel_version, $idx + 1);
        chomp($soc);
    }
    return $soc;
}

sub get_product_name {
    my $product = `sysctl -n hw.model`;
    chomp($product);
    return $product;
}

# Per 19677210, there's some evidence that sending back-to-back thermtune commands too quickly can cause
# failures, so wrap all thermtune commands in a helper that enforces a post-command delay.
sub send_thermtune_command {
    my $arg = shift(@_);
    system("thermtune $arg; sleep 2");
}

sub trim_in { for (@_) { s/^\s+|\s+$//g } }

sub get_die_temp {
    my $sensor_4cc = shift(@_);
    my $temp = `thermhid $sensor_4cc | tail -n 1 | cut -c 47-60`;
    chomp($temp);
    trim_in($temp);
    return $temp;
}

sub get_kDVD1 {
    my $factor = `powerctrl Factor1 | cut -f 2 -d ":"`;
    chomp($factor);
    trim_in($factor);
    return $factor;
}

sub start_cpu_virus {
    my $cpu_virus_name = shift(@_);
    system("clpcctrl QoSMinPerformance=1.0 > /dev/null");
    system("taskpolicy -b $cpu_virus_name -n 0 > /dev/null &");
}

sub stop_cpu_virus {
    my $cpu_virus_name = shift(@_);
    system("clpcctrl QoSMinPerformance=0.3 > /dev/null");
    system("killall -9 $cpu_virus_name");
}

sub description_implies_die_temp {
    my $desc = shift(@_);
    if ($desc =~ /(TC[0-9][iax])/) { return 1; }
    if ($desc =~ /(TH[0-9][iax])/) { return 1; }
    if ($desc =~ /PMGR SOC Die Temp Sensor/) { return 1; }
    if ($desc =~ /[CTA]CC Temp Sensor/) { return 1; }
    return 0;
}

sub field_must_be_valid {
    my $header_field = shift(@_);
    for my $check_field (@skin_model_4CCs) {
        if (index($header_field, $check_field) != -1) {
            # Description string includes 4CC of a skin model, so field is definitely *not* info-only
            return 1;
        }
    }
    
    # Die temps are a potentially required non-skin model field, given the slow die loop and Lifetime Servo
    if (description_implies_die_temp($header_field)) {
        if ($header_field =~ /Avg:/) {
            # Average die temps are generally required by the slow loop
            if (($header_field =~ /Avg: PMGR SOC Die Temp Sensor1/) && (grep { /$product_name/ } ("N41", "N42", "N48", "N49", "P101", "P102", "P103", "P105", "P106", "P107"))) {
                # These products are exceptions; each has a slow die loop that operates on the first average die temp sensor only, not the max of both
                return 0;
            } else {
                return 1;
            }
        } elsif ($header_field =~ /Max:/) {
            # Max die temps are required only by products that implement Lifetime Servo
            return $product_uses_lifetime_servo;
        }

        # Die temps are otherwise info-only
        return 0;
    }

    # The gas-gauge battery temp sensor (if present in the product plist) must always be valid
    if ($header_field =~ /TG0B/) {
        return 1;
    }
    
    # Field is otherwise info-only
    return 0;
}

sub field_value_invalid {
    my $header_field = shift(@_);
    my $check_value = shift(@_);

    # Set somewhat arbitrary validity ranges for die temp and other (including skin) temp outputs, padding somewhat
    # to allow for higher ambient conditions in the BATS test rack.  These ranges are only intended to catch gross
    # failures, such as a skin model operating on an input consisting of the info-only indicator value of -127 C.
    if (description_implies_die_temp($header_field)) {
        return (($check_value < 2000) || ($check_value > 5500));
    } else {
        return (($check_value < 2000) || ($check_value > 4300));
    }
}
