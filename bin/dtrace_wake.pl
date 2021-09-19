#!/usr/bin/env perl
#   Copyright 2014 Apple Inc. All rights reserved.

use strict;
use warnings;
no warnings 'portable';
use File::Temp qw/tempfile/;
use POSIX qw/strftime/;
use Getopt::Long;
$| = 1;


#!/bin/sh
#
#	wake.sh
#
#	Requirements:
#		1) Symbol-rich SpringBoard.app, backboardd, and wakemonitor dSYMs
#
#	Livetrace:
#		1) To enable livetracing, sync this script into:
#			/usr/local/lib/livetrace/tracers/
#		2) Enable livetracing in Internal Settings
#		3) Retrieve logs from:
#   		/var/logs/CrashReporter

sub gestalt_query {
    my ($key) = @_;
    my $result = `gestalt_query -undecorated $key`;
    chomp($result);
    return $result;
}

my $DEVICE_N94 = 4.5;
my $DEVICE_N41 = 5.0;
my $DEVICE_N48 = 5.1;
my $DEVICE_N51 = 5.5;
my $DEVICE_N56 = 6.0;
my $DEVICE_N66 = 7.1;
my $model_str = gestalt_query("HWModelStr");
my $device;
if ($model_str =~ /N94/) {
    $device = $DEVICE_N94;
} elsif ($model_str =~ /N41|N42/) {
    $device = $DEVICE_N41;
} elsif ($model_str =~ /N48|N49/) {
    $device = $DEVICE_N48;
} elsif ($model_str =~ /N51|N53/) {
    $device = $DEVICE_N51;
} elsif ($model_str =~ /N56|N61/) {
    $device = $DEVICE_N56;
} elsif ($model_str =~ /N66|N71/) {
    $device = $DEVICE_N66;
}

my $build  = gestalt_query("BuildVersion");
my $swvers = gestalt_query("ProductVersion");

sub main {
    get_options();

    printf("Detected $model_str running iOS $swvers ($build)\n");
    enable_wakemonitor();
    check_dsyms();

    create_dtrace();
    exec_dtrace();
}

my %opts = ();
sub get_options {
    GetOptions(\%opts, "stockholm!");

    if ($opts{stockholm} && $device < $DEVICE_N56) {
        print STDERR "There is no Stockholm on this device!\n";
        exit(1);
    }
}

my $print_stacks = 0;
my $stacks = $print_stacks ? "stack(200); ustack(200);" : "";

sub enable_wakemonitor {
    `touch /var/root/Library/Caches/com.apple.wakemonitor`;
    `touch /var/mobile/Library/Caches/com.apple.wakemonitor`;
}

sub get_uuid {
    my ($dsym) = @_;
    if ($dsym =~ /^(.*)\.dSYM$/) {
        my $path = $1;
        my $otool_out;
        if ($path =~ /([^\/]+)\.app$/) {
            $otool_out = `otool -l $path/$1 | grep uuid`;
        } elsif ($path =~ /\/([^\/]+)\.framework$/) {
            $otool_out = `otool -l $path/$1 | grep uuid`;
        } else {
            $otool_out = `otool -l $path | grep uuid`;
        }
        if ($otool_out =~ /\s+uuid\s+(.*)$/) {
            return $1;
        }
    }
    return "unknown-uuid";
}

sub check_dsyms {
    my $missing_dsyms = 0;
    my @required_dsyms = qw(/System/Library/CoreServices/SpringBoard.app.dSYM
                            /usr/libexec/backboardd.dSYM
                            /usr/local/bin/wakemonitor.dSYM);
    if ($opts{stockholm}) {
        push(@required_dsyms, "/System/Library/Frameworks/PassKit.framework/passd.dSYM");
        push(@required_dsyms, "/System/Library/Frameworks/PassKit.framework.dSYM");
        push(@required_dsyms, "/usr/libexec/nfcd.dSYM");
        push(@required_dsyms, "/usr/libexec/seld.dSYM");
    }

    for my $dsym (@required_dsyms) {
        if (! -d $dsym) {
            my $uuid = get_uuid($dsym);
            printf STDERR "Could not find $dsym <$uuid>.\n";
            $missing_dsyms = 1;
        }
    }

    if ($missing_dsyms) {
        exit(1);
    }
}

my @dtrace_script = ();

sub create_dtrace {
    my $printFormat = "%7d%15s%70s %6s %10d/%x\\n";

    sub add_probe {
        my $function = shift;
        my $predicate = shift;
        my $actions = join("\n    ", @_);

        my $probe_str;
        if ($predicate) {
            $probe_str = "$function\n/$predicate/\n{\n    $actions\n}\n";
        } else {
            $probe_str = "$function\n{\n    $actions\n}\n";
        }
        push(@dtrace_script, $probe_str);
    }

    push(@dtrace_script, "#pragma D option quiet\n");
    push(@dtrace_script, "#pragma D option strsize=64\n");
    push(@dtrace_script, "#pragma D option bufsize=512k\n");
    push(@dtrace_script, "#pragma D option dynvarsize=64k\n");
    push(@dtrace_script, "#pragma D option aggsize=64k\n");
    push(@dtrace_script, "#pragma D option aggsize=64k\n");


    add_probe("BEGIN", undef,
              'start = timestamp;',
              'wake = 0;',
              'wakeDone = 0;',
              'woke = 0;',
              'swaps = 0;',
              'insb = 0;',
              'in_flush = 0;',
              'in_observer = 0;',
              'in_swap = 0;',
              'in_power_change = 0;',
              'try_backlight = 0;',
              'deadline_start = 0;',
              'lcd_on_time = 0;',
              '',
              'printf("Ready...\n");',
              'printf("\n");',
              'printf("%7s%15s%70s %6s %10s %10s\n", "Time", "Process", "Function", "", "CPU/Tid", "timestamp/vtimestamp");',
        );

    # Wake starts when processor_shutdown returns (the kernel has been fully loaded by the LLB).
    add_probe("fbt:mach_kernel:processor_shutdown:return", undef,
              "wake = timestamp;",
              "swaps = 0;",
              "woke = 0;",
              "wakeDone = 0;",
              "printf(\"%7d     (%8d)%70s %6s %10d/%x\\n\", 0, (wake - start) / 1000, probefunc, probename, cpu, tid);",
              $stacks);


    # START TEMP PROBES FOR DEBUGGING
    my @debug_probes = ();

    if ($swvers =~ /^6/) {
        push(@debug_probes, 'pid$pid_SpringBoard:SpringBoard:??SBAwayController?updateOrientationForUndim?:entry');
        push(@debug_probes, 'pid$pid_SpringBoard:SpringBoard:??SBAwayController?updateOrientationForUndim?:return');
    } elsif ($swvers =~ /^7/) {
        push(@debug_probes, 'pid$pid_SpringBoard:SpringBoard:??SBLockScreenViewControllerBase?updateOrientationForUndim?:entry');
        push(@debug_probes, 'pid$pid_SpringBoard:SpringBoard:??SBLockScreenViewControllerBase?updateOrientationForUndim?:return');
    } elsif ($swvers >= 8) {
        push(@debug_probes, 'pid$pid_SpringBoard:SpringBoard:??SBLockScreenViewControllerBase?updateOrientationForUndim?:entry');
        push(@debug_probes, 'pid$pid_SpringBoard:SpringBoard:??SBLockScreenViewControllerBase?updateOrientationForUndim?:return');
    }

    push(@debug_probes, 'pid$pid_backboardd:backboardd:BKAccelerometerGetNonFlatDeviceOrientation:entry');
    push(@debug_probes, 'pid$pid_backboardd:backboardd:BKAccelerometerGetNonFlatDeviceOrientation:return');

    # Actual probes go here.
    my @main_probes = ();

    #  Unblanking and LCD Power-On

    #   1) Springboard receives an unlock event and calls sbblankscreen. It schedules a call to CoreAnimation
    #      to unblank the screen on the next turn of the run loop. This takes ~75ms...
    #
    #         SpringBoard`SBBlankScreen
    #         SpringBoard`_SBSetBacklightFactor+0x228
    #         SpringBoard`-[SpringBoard setBacklightFactor:keepTouchOn:]+0x55
    #         SpringBoard`-[SBAwayController attemptUnlockFromSource:]+0x59
    #         SpringBoard`-[SpringBoard menuButtonDown:]+0x20b
    #         QuartzCore`CA::WindowServer::IOMFBServer::set_enabled(bool)+0x1b

#     if ($swvers =~ /^6/) {
#         push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBAwayController?attemptUnlock*:entry');
#         push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBAwayController?attemptUnlock*:return');

#         push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SpringBoard?setBacklightFactor*:entry');
#         push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SpringBoard?setBacklightFactor*:return');

#         push(@main_probes, 'fbt:com.apple.driver.Apple*CLCD:*do_power_state_changeEv:entry');
#         push(@main_probes, 'fbt:com.apple.driver.Apple*CLCD:*do_power_state_changeEv:return');
#     } elsif ($swvers =~ /^7/) {
#         push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBLockScreenManager?unlockUIFromSource?withOptions??:entry');
#         push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBLockScreenManager?unlockUIFromSource?withOptions??:retry');

#         push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBBacklightController?setBacklightFactor?source??:entry');
#         push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBBacklightController?setBacklightFactor?source??:retry');

#         push(@main_probes, 'fbt:com.apple.driver.Apple*CLCD:*do_power_state_changeEv:entry');
#         push(@main_probes, 'fbt:com.apple.driver.Apple*CLCD:*do_power_state_changeEv:retry');
#     } elsif ($swvers >= 8) {
#         push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBLockScreenManager?unlockUIFromSource?withOptions??:entry');
#         push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBLockScreenManager?unlockUIFromSource?withOptions??:return');

#         push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBBacklightController?setBacklightFactor?source??:entry');
#         push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBBacklightController?setBacklightFactor?source??:return');

#         push(@main_probes, 'fbt:com.apple.driver.Apple*LCD:*Apple*LCD*_lcdEnable*:entry');
#         push(@main_probes, 'fbt:com.apple.driver.Apple*LCD:*Apple*LCD*_lcdEnable*:return');
#     }

#     push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SpringBoard?_menuButtonDown??:entry');
#     push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SpringBoard?_menuButtonDown??:return');

#     push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SpringBoard?_handlePhysicalButtonEvent??:entry');
#     push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SpringBoard?_handlePhysicalButtonEvent??:return');

#     #push(@main_probes, 'pid$pid_backboardd:backboardd:_BKHandleIOHIDEventFromSender:entry');
#     #push(@main_probes, 'pid$pid_backboardd:backboardd:_BKHandleIOHIDEventFromSender:return');

#     push(@main_probes, 'pid$pid_backboardd:backboardd:BKSendHIDEventToClientWithDestination:entry');
#     push(@main_probes, 'pid$pid_backboardd:backboardd:BKSendHIDEventToClientWithDestination:return');

#     if ($device > $DEVICE_N94) {
#         push(@main_probes, 'fbt:com.apple.driver.AppleCS42L67Audio:_ZN17AppleCS42L67Audio11enableAudioEb:entry');
#         push(@main_probes, 'fbt:com.apple.driver.AppleCS42L67Audio:_ZN17AppleCS42L67Audio11enableAudioEb:return');
#     }

#     #push(@main_probes, 'pid$pid_SpringBoard:UIKit:_UpdateBatteryStatus:return');

#     push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBOrientationLockManager?_updateLockStateWithOrientation?forceUpdateHID?changes??:entry');
#     push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBOrientationLockManager?_updateLockStateWithOrientation?forceUpdateHID?changes??:return');

#     push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBOrientationLockManager?setLockOverrideEnabled?forReason??:entry');
#     push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBOrientationLockManager?setLockOverrideEnabled?forReason??:return');

    if (!$opts{stockholm}) {
        push(@main_probes, 'pid$pid_SpringBoard:BackBoardServices:BKSHIDServicesLockOrientation:entry');
        push(@main_probes, 'pid$pid_SpringBoard:BackBoardServices:BKSHIDServicesLockOrientation:return');

        push(@main_probes, 'pid$pid_SpringBoard:BackBoardServices:BKSHIDServicesSetBacklightFactorWithFadeDurationSilently:entry');
        push(@main_probes, 'pid$pid_SpringBoard:BackBoardServices:BKSHIDServicesSetBacklightFactorWithFadeDurationSilently:return');

        push(@main_probes, 'pid$pid_SpringBoard:BackBoardServices:BKSHIDServicesSetBacklightFactorWithFadeDuration:entry');
        push(@main_probes, 'pid$pid_SpringBoard:BackBoardServices:BKSHIDServicesSetBacklightFactorWithFadeDuration:return');

        push(@main_probes, 'pid$pid_backboardd:backboardd:BKBacklightSetProperty:entry');
        push(@main_probes, 'pid$pid_backboardd:backboardd:BKBacklightSetProperty:return');

        push(@main_probes, 'pid$pid_backboardd:backboardd:_BKHIDBacklightLastRequestedFactor:entry');
        push(@main_probes, 'pid$pid_backboardd:backboardd:_BKHIDBacklightLastRequestedFactor:return');

        push(@main_probes, 'pid$pid_backboardd:backboardd:_BKHIDUpdateLastRequestedBacklightFactor:entry');
        push(@main_probes, 'pid$pid_backboardd:backboardd:_BKHIDUpdateLastRequestedBacklightFactor:return');

        push(@main_probes, 'pid$pid_backboardd:backboardd:__BKHIDSetBacklightFactorWithFadeDuration_block_invoke:entry');
        push(@main_probes, 'pid$pid_backboardd:backboardd:__BKHIDSetBacklightFactorWithFadeDuration_block_invoke:return');

        push(@main_probes, 'pid$pid_backboardd:backboardd:BKProximitySensorHandleProximityEvent:entry');
        push(@main_probes, 'pid$pid_backboardd:backboardd:BKProximitySensorHandleProximityEvent:return');

        # Too noisy
        #push(@main_probes, 'pid$pid_backboardd:backboardd:BKAccelerometerHandleEvent:entry');
        #push(@main_probes, 'pid$pid_backboardd:backboardd:BKAccelerometerHandleEvent:return');

        push(@main_probes, 'pid$pid_backboardd:BackBoardServices:BKSDisplayServicesSetScreenBlanked:entry');
        push(@main_probes, 'pid$pid_backboardd:BackBoardServices:BKSDisplayServicesSetScreenBlanked:return');

        # too noisy
        #push(@main_probes, 'fbt:com.apple.iokit.IOHIDFamily:_ZN*AppleEmbeddedHIDEventService*dispatch*EventEy*:entry');
        #push(@main_probes, 'fbt:com.apple.iokit.IOHIDFamily:_ZN*AppleEmbeddedHIDEventService*dispatch*EventEy*:return');

        push(@main_probes, 'pid$pid_backboardd:backboardd:BKAccelerometerSetOrientationEventsEnabled:entry');
        push(@main_probes, 'pid$pid_backboardd:backboardd:BKAccelerometerSetOrientationEventsEnabled:return');

        push(@main_probes, 'pid$pid_backboardd:backboardd:??BKAccelerometerInterface?_updateSettings?:entry');
        push(@main_probes, 'pid$pid_backboardd:backboardd:??BKAccelerometerInterface?_updateSettings?:return');

        push(@main_probes, 'pid$pid_backboardd:backboardd:_BKHIDXXSetOrientationClient:entry');
        push(@main_probes, 'pid$pid_backboardd:backboardd:_BKHIDXXSetOrientationClient:return');

        push(@main_probes, 'pid$pid_backboardd:backboardd:_HandleOrientationEvent:entry');
        push(@main_probes, 'pid$pid_backboardd:backboardd:_HandleOrientationEvent:return');

        push(@main_probes, 'pid$pid_backboardd:BackBoardServices:BKSDisplayBrightnessRestoreSystemBrightness:entry');
        push(@main_probes, 'pid$pid_backboardd:BackBoardServices:BKSDisplayBrightnessRestoreSystemBrightness:return');

        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBLockScreenViewController?_startFadeInAnimationForBatteryView??:entry');
        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBLockScreenViewController?_startFadeInAnimationForBatteryView??:return');

        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SpringBoard?updateOrientationDetectionSettings?:entry');
        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SpringBoard?updateOrientationDetectionSettings?:return');

        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SpringBoard?updateNativeOrientationAndMirroredDisplays??:entry');
        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SpringBoard?updateNativeOrientationAndMirroredDisplays??:return');

        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SpringBoard?_currentNonFlatDeviceOrientation?:entry');
        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SpringBoard?_currentNonFlatDeviceOrientation?:return');

        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBWindow?_initWithScreen?layoutStrategy?debugName?scene??:entry');
        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBWindow?_initWithScreen?layoutStrategy?debugName?scene??:return');

        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBScreenFadeAnimationController?_createFadeWindowForFadeIn??:entry');
        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBScreenFadeAnimationController?_createFadeWindowForFadeIn??:return');

        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBSceneManager?sceneManager?didCreateScene?withClient??:entry');
        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBSceneManager?sceneManager?didCreateScene?withClient??:return');

        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBSceneManagerController?sceneManager?scene?willTransitionToState??:entry');
        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBSceneManagerController?sceneManager?scene?willTransitionToState??:return');

        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBStatusBarStyleOverridesAssertionManager?postStatusStringsForForegroundApplications??:entry');
        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBStatusBarStyleOverridesAssertionManager?postStatusStringsForForegroundApplications??:return');

        push(@main_probes, 'pid$pid_SpringBoard:SpringBoardFoundation:??SBFLockScreenDateView?setDate??:entry');
        push(@main_probes, 'pid$pid_SpringBoard:SpringBoardFoundation:??SBFLockScreenDateView?setDate??:return');

        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBAppStatusBarManager?setStatusBarAlpha??:entry');
        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBAppStatusBarManager?setStatusBarAlpha??:return');

        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBBacklightController?turnOnScreenFullyWithBacklightSource??:entry');
        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBBacklightController?turnOnScreenFullyWithBacklightSource??:return');

        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBBacklightController?_animateBacklightToFactor?duration?source?silently?completion??:entry');
        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBBacklightController?_animateBacklightToFactor?duration?source?silently?completion??:return');

        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:_SBSetBacklightFactor:entry');
        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:_SBSetBacklightFactor:return');

        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:_SBSystemGesturesChangeGestureAndRecognitionState:entry');
        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:_SBSystemGesturesChangeGestureAndRecognitionState:return');

        push(@main_probes, 'pid$pid_SpringBoard:SpringBoardUIServices:??SBUIBiometricEventMonitor?noteScreenWillTurnOn?:entry');
        push(@main_probes, 'pid$pid_SpringBoard:SpringBoardUIServices:??SBUIBiometricEventMonitor?noteScreenWillTurnOn?:return');

        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBLockScreenViewController?setInScreenOffMode?forAutoUnlock??:entry');
        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBLockScreenViewController?setInScreenOffMode?forAutoUnlock??:return');

        if ($device > $DEVICE_N94) {
            push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBLockScreenViewController?_handleDisplayTurnedOn*:entry');
            push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBLockScreenViewController?_handleDisplayTurnedOn*:return');
        }

        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBLockScreenViewController?_handleBacklightFadeEnded?:entry');
        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBLockScreenViewController?_handleBacklightFadeEnded?:return');

        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBScreenTimeTrackingController?_setActiveCategory??:entry');
        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBScreenTimeTrackingController?_setActiveCategory??:return');

        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBLockScreenView?startAnimating?:entry');
        push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:??SBLockScreenView?startAnimating?:return');

        push(@main_probes, 'pid$pid_SpringBoard:UIKit:??UIMotionEvent?_enablePeakDetectionIfNecessary?:entry');
        push(@main_probes, 'pid$pid_SpringBoard:UIKit:??UIMotionEvent?_enablePeakDetectionIfNecessary?:return');
    }

    #  2) Finally, on the next turn of the run loop, we ask CoreAnimation to unblank. This schedules
    #     render_for_time immediately.
    #
    #         QuartzCore`CA::Render::Server::add_callback(double, CA::Render::Server::CallbackBehavior, void (*)(double, void*), void*)
    #         QuartzCore`CA::WindowServer::Server::set_next_update(double, double)+0x6b
    #         QuartzCore`CA::WindowServer::IOMFBServer::set_next_update(double, double)+0xad
    #         QuartzCore`CA::WindowServer::Server::delete_context(CA::Render::Context*)+0x129
    #         QuartzCore`CA::Render::post_notification(CA::Render::NotificationName, CA::Render::Object*, void*, bool)+0xe7
    #         QuartzCore`CA::Render::Context::destroy()+0x73
    #         QuartzCore`CA::WindowServer::Server::destroy_blank_context()+0x15
    #         QuartzCore`CA::WindowServer::Server::set_blanked(bool)+0x5b <---
    #         QuartzCore`-[CAWindowServerDisplay setBlanked:]+0x27
    #         Foundation`__NSFireDelayedPerform+0x19d
    #
    #  3) render_for_time checks the blanked flag and requests that we enable the display. iomfb
    #     sets some flags and fires an interrupt.
    #
    #         libsystem_kernel.dylib`mach_msg_trap+0x14
    #         IOKit`io_connect_method+0x119
    #         IOKit`IOConnectCallMethod+0xa3
    #         IOKit`IOConnectCallScalarMethod+0x23
    #         IOMobileFramebuffer`kern_RequestPowerChange+0x27
    #         IOMobileFramebuffer`IOMobileFramebufferRequestPowerChange+0x1f
    #         QuartzCore`CA::WindowServer::IOMFBDisplay::set_enabled_(bool)+0x1f
    #         QuartzCore`CA::WindowServer::IOMFBDisplay::set_enabled(bool)+0xd5
    #         QuartzCore`CA::WindowServer::IOMFBServer::set_enabled(bool)+0x1b
    #         QuartzCore`CA::WindowServer::Server::render_for_time(double, CVTimeStamp const*)+0x141
    #         QuartzCore`CA::Render::Server::run_callbacks()+0x8b
    #         QuartzCore`CA::Render::Server::server_thread(void*)+0xcb
    #         QuartzCore`thread_fun+0x11
    #         libsystem_c.dylib`_pthread_start+0x141
    #         libsystem_c.dylib`thread_start+0x8
    #
    #         IOMobileGraphicsFamily`IOMobileFramebuffer::set_api_power_state_gated(unsigned long, IOService*)+0x2
    #         IOMobileGraphicsFamily`IOMobileFramebufferUserClient::request_power_change(unsigned int)+0x89
    #         mach.development.s5l8930x`shim_io_connect_method_scalarI_scalarO+0x15d
    #         mach.development.s5l8930x`IOUserClient::externalMethod(unsigned int, IOExternalMethodArguments*, IOExternalMethodDispatch*, OSObject*, void*)+0x229
    #         mach.development.s5l8930x`is_io_connect_method+0xfb
    #         mach.development.s5l8930x`iokit_server_routine+0x4aff
    #         mach.development.s5l8930x`ipc_kobject_server+0xd1
    #         mach.development.s5l8930x`ipc_kmsg_send+0x71
    #         mach.development.s5l8930x`mach_msg_overwrite_trap+0x73
    #         mach.development.s5l8930x`fleh_swi+0x100
    #
    #  4) The interrupt triggers on a separate iomfb ioworkloop. the lcd driver waits ~128ms to power on the display.
    #
    #         ApplePinotLCD`ApplePinotLCD::_lcdEnable(bool, void*, void (*)(void*, bool), unsigned long long*)+0x2
    #         AppleCLCD`AppleCLCD::do_power_state_change()+0x351
    #         IOMobileGraphicsFamily`IOMobileFramebuffer::set_power_state_gated(unsigned long, IOService*)+0x191
    #         IOMobileGraphicsFamily`IOMobileFramebuffer::power_state_change_interrupt(IOInterruptEventSource*, int)+0x21
    #         mach.development.s5l8930x`IOInterruptEventSource::checkForWork()+0x45
    #         mach.development.s5l8930x`IOWorkLoop::runEventSources()+0xcb
    #         mach.development.s5l8930x`IOWorkLoop::threadMain()+0x4b
    #         mach.development.s5l8930x`Call_continuation+0x1c

#     push(@main_probes, 'pid$pid_backboardd:backboardd:??BKProximitySensorInterface?enableProximityDetectionWithMode??:entry');
#     push(@main_probes, 'pid$pid_backboardd:backboardd:??BKProximitySensorInterface?enableProximityDetectionWithMode??:return');

#     push(@main_probes, 'pid$pid_backboardd:backboardd:BKDisplayWillUnblank:entry');
#     push(@main_probes, 'pid$pid_backboardd:backboardd:BKDisplayWillUnblank:return');

#     push(@main_probes, 'pid$pid_backboardd:QuartzCore:CA??WindowServer??Server??*blank*:entry');
#     push(@main_probes, 'pid$pid_backboardd:QuartzCore:CA??WindowServer??Server??*blank*:return');

#     push(@main_probes, 'pid$pid_backboardd:IOMobileFramebuffer:IOMobileFramebufferRequestPowerChange:entry');
#     push(@main_probes, 'pid$pid_backboardd:IOMobileFramebuffer:IOMobileFramebufferRequestPowerChange:return');

#     push(@main_probes, 'pid$pid_backboardd:MultitouchSupport:mt_InitializeAlgorithmsForDevice:entry');
#     push(@main_probes, 'pid$pid_backboardd:MultitouchSupport:mt_InitializeAlgorithmsForDevice:return');

#     push(@main_probes, 'pid$pid_backboardd:backboardd:??BKProximitySensorInterface?requestProximityMode??:entry');
#     push(@main_probes, 'pid$pid_backboardd:backboardd:??BKProximitySensorInterface?requestProximityMode??:return');

#     push(@main_probes, 'pid$pid_SpringBoard:BackBoardServices:BKSDisplayServicesWillUnblank:entry');
#     push(@main_probes, 'pid$pid_SpringBoard:BackBoardServices:BKSDisplayServicesWillUnblank:return');

#     push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:SBBlankScreen:entry');
#     push(@main_probes, 'pid$pid_SpringBoard:SpringBoard:SBBlankScreen:return');

#     push(@main_probes, 'pid$pid_SpringBoard:IOMobileFramebuffer:IOMobileFramebufferRequestPowerChange:entry');
#     push(@main_probes, 'pid$pid_SpringBoard:IOMobileFramebuffer:IOMobileFramebufferRequestPowerChange:return');

#     if (!$opts{stockholm}) {
#         push(@main_probes, 'pid$pid_wakemonitor:wakemonitor:backlightStateChanged:entry');
#         push(@main_probes, 'pid$pid_wakemonitor:wakemonitor:backlightStateChanged:return');
#     }

#     push(@main_probes, 'pid$pid_wakemonitor:wakemonitor:systemWokeUp:entry');
#     push(@main_probes, 'pid$pid_wakemonitor:wakemonitor:systemWokeUp:return');

#     push(@main_probes, 'fbt:*:_ZN19IOMobileFramebuffer21set_power_state_gatedEmP9IOService:entry');
#     push(@main_probes, 'fbt:*:_ZN19IOMobileFramebuffer21set_power_state_gatedEmP9IOService:return');

#     push(@main_probes, 'fbt:com.apple.iokit.IOMobileGraphicsFamily:_ZN19IOMobileFramebuffer5startEP9IOService:entry');
#     push(@main_probes, 'fbt:com.apple.iokit.IOMobileGraphicsFamily:_ZN19IOMobileFramebuffer5startEP9IOService:return');

#     push(@main_probes, 'fbt:com.apple.iokit.IOMobileGraphicsFamily:_ZN19IOMobileFramebuffer28power_state_change_interruptEP22IOInterruptEventSourcei:entry');
#     push(@main_probes, 'fbt:com.apple.iokit.IOMobileGraphicsFamily:_ZN19IOMobileFramebuffer28power_state_change_interruptEP22IOInterruptEventSourcei:return');

#     if ($device >= $DEVICE_N51) {
#         push(@main_probes, 'fbt:com.apple.driver.AppleLMBacklight:_ZN16AppleLMBacklight15backlightEnableEb:entry');
#         push(@main_probes, 'fbt:com.apple.driver.AppleLMBacklight:_ZN16AppleLMBacklight15backlightEnableEb:return');
#     } else {
#         push(@main_probes, 'fbt:com.apple.driver.AppleH*CLCD:*safe_enable_backlightEv:entry');
#         push(@main_probes, 'fbt:com.apple.driver.AppleH*CLCD:*safe_enable_backlightEv:return');
#     }

#     if (!$opts{stockholm}) {
#         push(@main_probes, 'fbt:com.apple.driver.AppleS5L8940XDWI:_ZN33AppleS5L8940XDWIBacklightFunction12callFunctionEPvS0_S0_:entry');
#         push(@main_probes, 'fbt:com.apple.driver.AppleS5L8940XDWI:_ZN33AppleS5L8940XDWIBacklightFunction12callFunctionEPvS0_S0_:return');
#     }

#     push(@main_probes, 'pid$pid_SpringBoard:SpringBoardFoundation:??SBFLockScreenDateView?setDate??:entry');
#     push(@main_probes, 'pid$pid_SpringBoard:SpringBoardFoundation:??SBFLockScreenDateView?setDate??:return');

#     push(@main_probes, 'pid$pid_SpringBoard:IOMobileFramebuffer:kern_EnableVSyncNotifications:entry');
#     push(@main_probes, 'pid$pid_SpringBoard:IOMobileFramebuffer:kern_EnableVSyncNotifications:return');

#     push(@main_probes, 'pid$pid_backboardd:IOMobileFramebuffer:kern_RequestPowerChange:entry');
#     push(@main_probes, 'pid$pid_backboardd:IOMobileFramebuffer:kern_RequestPowerChange:return');


    if ($opts{stockholm}) {
        # From Stockholm team: These are the major events, in order
        # 1.  Triggers wake_stockhom in SEP driver.
        push(@main_probes, 'fbt:com.apple.driver.AppleStockholmControl:_ZN21AppleStockholmControl13setPowerStateEmP9IOService:entry');
        push(@main_probes, 'fbt:com.apple.driver.AppleStockholmControl:_ZN21AppleStockholmControl13setPowerStateEmP9IOService:return');

        # 2.  Indicates field ON event.
        if ($swvers >= 9) {
            push(@main_probes, 'pid$pid_nfcd:nfcd:??_NFHardwareManager?handleFieldChanged??:entry');
            push(@main_probes, 'pid$pid_nfcd:nfcd:??_NFHardwareManager?handleFieldChanged??:return');
        } else {
            push(@main_probes, 'pid$pid_nfcd:nfcd:??NFDaemon?driverDidDetectFieldChange??:entry');
            push(@main_probes, 'pid$pid_nfcd:nfcd:??NFDaemon?driverDidDetectFieldChange??:return');
        }

        # 3.  Authorize
        push(@main_probes, 'pid$pid_seld:seld:??NFCardManagerAgent?authorize?callback??:entry');
        push(@main_probes, 'pid$pid_seld:seld:??NFCardManagerAgent?authorize?callback??:return');
        push(@main_probes, 'pid$pid_seld:seld:*??NFCardManagerAgent?authorize?callback??*block_invoke*:entry');
        push(@main_probes, 'pid$pid_seld:seld:*??NFCardManagerAgent?authorize?callback??*block_invoke*:return');

        # 4.  Register
        if ($swvers >= 9) {
            push(@main_probes, 'pid$pid_nfcd:nfcd:??_NFHardwareManager?listener?shouldAcceptNewConnection??:entry');
            push(@main_probes, 'pid$pid_nfcd:nfcd:??_NFHardwareManager?listener?shouldAcceptNewConnection??:return');
        } else {
            push(@main_probes, 'pid$pid_nfcd:nfcd:??NFDaemon?q_registerConnection?info??:entry');
            push(@main_probes, 'pid$pid_nfcd:nfcd:??NFDaemon?q_registerConnection?info??:return');
        }

        if ($swvers >= 9) {
            push(@main_probes, 'pid$pid_nfcd:nfcd:??_NFContactlessPaymentSession?willStartSession?:entry');
            push(@main_probes, 'pid$pid_nfcd:nfcd:??_NFContactlessPaymentSession?willStartSession?:return');
        } else {
            push(@main_probes, 'pid$pid_nfcd:nfcd:??NFDaemon?q_registerEmbeddedCardEmulationController??:entry');
            push(@main_probes, 'pid$pid_nfcd:nfcd:??NFDaemon?q_registerEmbeddedCardEmulationController??:return');
        }

        if ($swvers >= 9) {
            push(@main_probes, 'pid$pid_nfcd:PN548_API?dylib:NFDriverSetConfiguration:entry');
            push(@main_probes, 'pid$pid_nfcd:PN548_API?dylib:NFDriverSetConfiguration:return');
        } else {
            push(@main_probes, 'pid$pid_nfcd:PN548_API?dylib:NFDriverSetMode:entry');
            push(@main_probes, 'pid$pid_nfcd:PN548_API?dylib:NFDriverSetMode:return');
        }

        # 5.  Indicates start of transaction event
        if ($swvers >= 9) {
            push(@main_probes, 'pid$pid_nfcd:nfcd:??_NFContactlessPaymentSession?handleTransactionStartEvent??:entry');
            push(@main_probes, 'pid$pid_nfcd:nfcd:??_NFContactlessPaymentSession?handleTransactionStartEvent??:return');
        } else {
            push(@main_probes, 'pid$pid_nfcd:nfcd:??NFCardEmulationController?handleTransactionStartEvent??:entry');
            push(@main_probes, 'pid$pid_nfcd:nfcd:??NFCardEmulationController?handleTransactionStartEvent??:return');
        }

        # 6.  Indicates end of transaction event
        if ($swvers >= 9) {
            push(@main_probes, 'pid$pid_nfcd:nfcd:??_NFContactlessPaymentSession?handleTransactionEndEvent??:entry');
            push(@main_probes, 'pid$pid_nfcd:nfcd:??_NFContactlessPaymentSession?handleTransactionEndEvent??:return');
        } else {
            push(@main_probes, 'pid$pid_nfcd:nfcd:??NFCardEmulationController?handleTransactionEndEvent??:entry');
            push(@main_probes, 'pid$pid_nfcd:nfcd:??NFCardEmulationController?handleTransactionEndEvent??:return');
        }

        # 7.  Deauthorize
        push(@main_probes, 'pid$pid_seld:seld:??NFCardManagerAgent?deauthorize??:entry');
        push(@main_probes, 'pid$pid_seld:seld:??NFCardManagerAgent?deauthorize??:return');

        # 8.  Unregister
        if ($swvers >= 9) {
            push(@main_probes, 'pid$pid_nfcd:nfcd:??_NFContactlessPaymentSession?endSession??:entry');
            push(@main_probes, 'pid$pid_nfcd:nfcd:??_NFContactlessPaymentSession?endSession??:return');
        } else {
            push(@main_probes, 'pid$pid_nfcd:nfcd:??NFDaemon?q_unregisterEmbeddedCardEmulationController?:entry');
            push(@main_probes, 'pid$pid_nfcd:nfcd:??NFDaemon?q_unregisterEmbeddedCardEmulationController?:return');
        }

        # From Passbook team:
        #         -[PDServer contactlessInterfaceDidEnterField:]
        push(@main_probes, 'pid$pid_passd:passd:??PDServer?contactlessInterfaceDidEnterField??:entry');
        push(@main_probes, 'pid$pid_passd:passd:??PDServer?contactlessInterfaceDidEnterField??:return');
        #         -[PDServer _handleContactlessPaymentInterfaceAlertActivated:]
        push(@main_probes, 'pid$pid_passd:passd:??PDServer?_handleContactlessPaymentInterfaceAlertActivated??:entry');
        push(@main_probes, 'pid$pid_passd:passd:??PDServer?_handleContactlessPaymentInterfaceAlertActivated??:return');
        #         -[PDServer _handleContactlessPaymentInterfaceAlertDeactivated:]
        push(@main_probes, 'pid$pid_passd:passd:??PDServer?_handleContactlessPaymentInterfaceAlertDeactivated??:entry');
        push(@main_probes, 'pid$pid_passd:passd:??PDServer?_handleContactlessPaymentInterfaceAlertDeactivated??:return');
        #         -[PDServer secureElement:didAuthorizeApplication:]
        push(@main_probes, 'pid$pid_passd:passd:??PDServer?secureElement?didAuthorizeApplication??:entry');
        push(@main_probes, 'pid$pid_passd:passd:??PDServer?secureElement?didAuthorizeApplication??:return');
        #         -[PDServer secureElement:didDeauthorizeApplication:]
        push(@main_probes, 'pid$pid_passd:passd:??PDServer?secureElement?didDeauthorizeApplication??:entry');
        push(@main_probes, 'pid$pid_passd:passd:??PDServer?secureElement?didDeauthorizeApplication??:return');
        #         -[PDContactlessInterface startCardEmulation]
        push(@main_probes, 'pid$pid_passd:passd:??PDContactlessInterface?startCardEmulation?:entry');
        push(@main_probes, 'pid$pid_passd:passd:??PDContactlessInterface?startCardEmulation?:return');
        #         -[PDContactlessInterface stopCardEmulation]
        push(@main_probes, 'pid$pid_passd:passd:??PDContactlessInterface?stopCardEmulation?:entry');
        push(@main_probes, 'pid$pid_passd:passd:??PDContactlessInterface?stopCardEmulation?:return');
        #         -[PDContactlessInterface cardEmulation:didEndTransaction:]
        push(@main_probes, 'pid$pid_passd:passd:??PDContactlessInterface?cardEmulation?didEndTransaction??:entry');
        push(@main_probes, 'pid$pid_passd:passd:??PDContactlessInterface?cardEmulation?didEndTransaction??:return');
        #         -[PKPassPaymentContainerView payStateView:revealingCheckmark:]  -- This is the "done" audio cue; not matching for some reason
        #push(@main_probes, 'pid$pid_PassbookUIService:PassKit:??PKPassPaymentContainerView?payStateView?revealingCheckmark??:entry');
        #push(@main_probes, 'pid$pid_PassbookUIService:PassKit:??PKPassPaymentContainerView?payStateView?revealingCheckmark??:return');
        push(@main_probes, 'pid$pid_PassbookUIService:AudioToolbox:AudioServicesPlaySystemSound:entry');
        push(@main_probes, 'pid$pid_PassbookUIService:AudioToolbox:AudioServicesPlaySystemSound:return');

        push(@main_probes, 'pid$pid_passd:passd:??PDContactlessInterface?cardEmulation?isSuspended??:entry');
        push(@main_probes, 'pid$pid_passd:passd:??PDContactlessInterface?cardEmulation?isSuspended??:return');

        #push(@main_probes, 'pid$pid_passd:PassKitCore:??PKAuthenticator?evaluatePolicy?completion??:entry');
        #push(@main_probes, 'pid$pid_passd:PassKitCore:??PKAuthenticator?evaluatePolicy?completion??:return');

        # Mesa points from inside Passbook
        #push(@main_probes, 'pid$pid_PassbookUIService:PassKit:??PKPassPaymentContainerView?_activateForPayment?:entry');
        #push(@main_probes, 'pid$pid_PassbookUIService:PassKit:??PKPassPaymentContainerView?_activateForPayment?:return');

        #push(@main_probes, 'pid$pid_PassbookUIService:PassKit:??PKPassPaymentContainerView?_startFingerprintAnimation?:entry');
        #push(@main_probes, 'pid$pid_PassbookUIService:PassKit:??PKPassPaymentContainerView?_startFingerprintAnimation?:return');

        # From Ariadne traces:
        # Causes a call to CLCopyMonitoredRegions:
        push(@main_probes, 'pid$pid_passd:passd:??PDRelevantPassProvider?_startCardSearchUpdatingWithCachedProximity?refreshingProximity?searchMode??:entry');
        push(@main_probes, 'pid$pid_passd:passd:??PDRelevantPassProvider?_startCardSearchUpdatingWithCachedProximity?refreshingProximity?searchMode??:return');

        #push(@main_probes, 'pid$pid_passd:passd:??PDServer?_launchContactlessPaymentInterface?:entry');
        #push(@main_probes, 'pid$pid_passd:passd:??PDServer?_launchContactlessPaymentInterface?:return');

        push(@main_probes, 'pid$pid_passd:passd:??PDSecureElement?activatePaymentApplication?completion??:entry');
        push(@main_probes, 'pid$pid_passd:passd:??PDSecureElement?activatePaymentApplication?completion??:return');

        push(@main_probes, 'pid$pid_passd:passd:??PDSecureElement?_archiveToDisk?:entry');
        push(@main_probes, 'pid$pid_passd:passd:??PDSecureElement?_archiveToDisk?:return');

        push(@main_probes, 'pid$pid_passd:SpringBoardServices:SBSUIActivateRemoteAlertWithLifecycleNotifications:entry');
        push(@main_probes, 'pid$pid_passd:SpringBoardServices:SBSUIActivateRemoteAlertWithLifecycleNotifications:return');

        push(@main_probes, 'pid$pid_passd:SpringBoardServices:SBSAcquireBiometricUnlockSuppressionAssertion:entry');
        push(@main_probes, 'pid$pid_passd:SpringBoardServices:SBSAcquireBiometricUnlockSuppressionAssertion:return');
    }

    my @probes = (@debug_probes, @main_probes);
    add_probe(join(",\n", @probes), "wake > 0",
              "this->t = timestamp;",
              #"this->vt = vtimestamp;",
              "self->t[probefunc, probename] = this->t;",
              #"self->vt[probefunc, probename] = this->vt;",
              "this->d = this->t - self->t[probefunc, \"entry\"];",
              #"this->vd = this->vt - self->vt[probefunc, \"entry\"];",
              "",
              "printf(\"$printFormat\", (this->t - wake) / 1000, execname, probefunc, probename, cpu, tid);",
              $stacks);

    if (!$opts{stockholm}) {
        add_probe('pid$pid_SpringBoard:IOMobileFramebuffer:IOMobileFramebufferRequestPowerChange:entry,
pid$pid_backboardd:IOMobileFramebuffer:IOMobileFramebufferRequestPowerChange:entry', "wake > 0",
                  'printf("%7d%15s%70s %6s", (timestamp - wake) / 1000, execname, probefunc, probename);',
                  'printf("\tFuncArgs:  %x, %x\n", arg0, arg1);',
                  $stacks,
            );

        add_probe('pid$pid_wakemonitor:wakemonitor:backlightStateChanged:entry', "wake > 0",
                  'printf("%7d%15s%70s %6s", (timestamp - wake) / 1000, execname, probefunc, probename);',
                  'printf("\tMessageType: %x\n", arg2);',
                  $stacks,
            );

        add_probe('pid$pid_wakemonitor:wakemonitor:backlightStateChanged:return', "wake > 0",);
    }

    add_probe('pid$pid_wakemonitor:libsystem_c.dylib:fopen:entry', "wake > 0",
              'printf("%7d%15s --- Writing Log For Wake Event\n", (timestamp - wake) / 1000, execname);',
              'wakeDone = 1;',
              $stacks);

    # backlight / display pipe synchronization:
    #
    # the backlight-power-on-is-safe-deadline is ~67ms after the lcd has finished turning on.
    #
    # if the backlight got turned on during do_power_state_change, then we have
    # already produced a frame way before the backlight power-on-is-safe
    # deadline.
    #
    # otherwise, if we turned on the backlight on swap_begin, then the backlight
    # may have been waiting for a valid frame from userland.
    #
    # however, if we are in swap_begin and had to wait in safe_enable_backlight,
    # then we produced a frame before the deadline, but had to wait until the
    # hardware was ready.
    #
    #           AppleSamsungSWI`AppleSamsungSWIBacklightFunction::callFunction(void*, void*, void*)+0x6
    #           AppleARMPlatform`AppleARMBacklight::setPropertiesGated(OSObject*)+0x433
    #           AppleARMPlatform`AppleARMBacklight::handleMessageGated(unsigned long, void*)+0x89
    #           mach.development.s5l8930x`IOCommandGate::runAction(int (*)(OSObject*, void*, void*, void*, void*), void*, void*, void*, void*)+0xe9
    #           AppleARMPlatform`AppleARMBacklight::message(unsigned long, IOService*, void*)+0x47
    #           AppleCLCD`AppleCLCD::safe_enable_backlight()+0x49
    #           AppleCLCD`AppleCLCD::swap_begin()+0x2b
    #           AppleDisplayPipe`AppleDisplayPipe::interruptHandler(OSObject*, void*, void*, void*, void*)+0x369
    #           mach.development.s5l8930x`IOInterruptEventSource::checkForWork()+0x45
    #           mach.development.s5l8930x`IOWorkLoop::runEventSources()+0xcb
    #           mach.development.s5l8930x`IOWorkLoop::threadMain()+0x4b
    #           mach.development.s5l8930x`Call_continuation+0x1c
    if ($swvers =~ /^6/) {
        add_probe("fbt:com.apple.driver.Apple*CLCD:*do_power_state_changeEv:entry",  undef, "in_power_change = 1;");
        add_probe("fbt:com.apple.driver.Apple*CLCD:*do_power_state_changeEv:return", undef, "in_power_change = 0;");

        add_probe("fbt:com.apple.driver.Apple*CLCD:*swap_beginEv:entry",  undef, "in_swap = 1;");
        add_probe("fbt:com.apple.driver.Apple*CLCD:*swap_beginEv:return", undef, "in_swap = 0;");
    } elsif ($swvers =~ /^7/) {
        add_probe("fbt:com.apple.driver.Apple*CLCD:*do_power_state_changeEv:entry",  undef, "in_power_change = 1;");
        add_probe("fbt:com.apple.driver.Apple*CLCD:*do_power_state_changeEv:return", undef, "in_power_change = 0;");
        add_probe("fbt:com.apple.driver.Apple*CLCD:*swap_beginEv:entry",  undef, "in_swap = 1;");
        add_probe("fbt:com.apple.driver.Apple*CLCD:*swap_beginEv:return", undef, "in_swap = 0;");
    } elsif ($swvers >= 8) {
        add_probe("fbt:com.apple.driver.Apple*:*do_power_state_change*:entry",  undef, "in_power_change = 1;");
        add_probe("fbt:com.apple.driver.Apple*:*do_power_state_change*:return", undef, "in_power_change = 0;");
        add_probe("fbt:com.apple.driver.Apple*:*swap_begin_gatedEv:entry",  undef, "in_swap = 1;");
        if ($device < $DEVICE_N51) {
            add_probe("fbt:com.apple.driver.Apple*:*swap_begin_gatedEv:return", undef, "in_swap = 0;");
        }
    }

    if ($device >= $DEVICE_N51) {
        add_probe("fbt:com.apple.driver.AppleLMBacklight:_ZN16AppleLMBacklight15backlightEnableEb:entry");
    } else {
        add_probe("fbt:com.apple.driver.Apple*CLCD:*safe_enable_backlightEv:entry", undef, "try_backlight = timestamp;");
    }

    if (!$opts{stockholm}) {
        add_probe("fbt:com.apple.driver.AppleS5L8940XDWI:_ZN33AppleS5L8940XDWIBacklightFunction12callFunctionEPvS0_S0_:entry", "wake > 0",
                  "woke = timestamp;",
                  "lcd_on_time = timestamp;",
                  "this->waited = (woke - try_backlight) / 1000;",
                  "this->deadline = (woke - deadline_start) / 1000;",
                  "printf(\"$printFormat\", (timestamp - wake) / 1000, execname, probefunc, probename, cpu, tid);",
                  "printf(\"%d\t\t\t(on %s; frame was %s by deadline; so had to wait %d us for hardware; total hardware wait: %d us)\\n\",",
                  "       (timestamp - wake) / 1000,",
                  "       in_power_change ? \"deadline\" : in_swap ? \"swap\" : \"???\",",
                  "       this->waited >= 0 ? \"ready\" : \"not ready\",",
                  "       this->waited,",
                  "       this->waited >= 0 ? this->deadline : 0);",
                  $stacks);

        add_probe("fbt:com.apple.driver.AppleS5L8940XDWI:_ZN33AppleS5L8940XDWIBacklightFunction12callFunctionEPvS0_S0_:return", undef,
                  "deadline_start = timestamp");
    }

    # Regular display updates; track the first at least n number of frames
    my $numberOfFramesToTrack = 20;
    my $swapCompleteProbe;
    if ($swvers =~ /^[67]/) {
        $swapCompleteProbe = "fbt:com.apple.iokit.IOMobileGraphicsFamily:_ZN19IOMobileFramebuffer13swap_completeEv:entry";
    } elsif ($swvers > 8) {
        $swapCompleteProbe = "fbt:com.apple.iokit.IOMobileGraphicsFamily:_ZN19IOMobileFramebuffer19swap_complete_gatedEv:entry";
    }

    add_probe($swapCompleteProbe, "wake > 0 && swaps < $numberOfFramesToTrack",  "swaps++;");
    add_probe($swapCompleteProbe, "wake > 0 && swaps >= $numberOfFramesToTrack && wakeDone == 1", "swaps = 0;", "wake = 0;");

    my @display_probes = ();
    if ($swvers =~ /^[67]/) {
        push(@display_probes, "fbt:com.apple.driver.Apple*DisplayPipe:_ZN16AppleDisplayPipe16program_hardwareEb:entry");
    } elsif ($swvers >= 8) {
        if ($device >= $DEVICE_N56) {
            # FIXME
        } else {
            push(@display_probes, "fbt:com.apple.driver.Apple*DisplayPipe:_ZN16AppleDisplayPipe22program_hardware_gatedEb:entry");
        }
    }

    push(@display_probes, $swapCompleteProbe);
        push(@display_probes, 'pid$pid_backboardd:QuartzCore:CA??WindowServer??Server??render_for_time*:entry');
        push(@display_probes, 'pid$pid_backboardd:QuartzCore:CA??WindowServer??Server??render_for_time*:return');

    if (!$opts{stockholm}) {
        for my $probe (@display_probes) {
            add_probe($probe, "wake > 0 && swaps < $numberOfFramesToTrack",
                      "printf(\"$printFormat\", (timestamp - wake) / 1000, execname, probefunc, probename, cpu, tid);",
                      $stacks);
        }

        add_probe('pid$pid_SpringBoard:QuartzCore:CA??Transaction??observer_callback*:entry',  undef, "in_observer = 1;");
        add_probe('pid$pid_SpringBoard:QuartzCore:CA??Transaction??observer_callback*:return', undef, "in_observer = 0;");

        add_probe('pid$pid_SpringBoard:QuartzCore:CA??Transaction??flush*:entry',  undef, "in_flush = 1;");
        add_probe('pid$pid_SpringBoard:QuartzCore:CA??Transaction??flush*:return', undef, "in_flush = 0;");

        add_probe('pid$pid_SpringBoard:QuartzCore:CA??Transaction??commit*:entry,
pid$pid_SpringBoard:QuartzCore:CA??Transaction??commit??:return',
                  "wake > 0 && swaps < $numberOfFramesToTrack",
                  "printf(\"$printFormat\", (timestamp - wake) / 1000, execname, probefunc, probename, cpu, tid);",
#              "printf(\"\t(from %s)\\n\", in_flush ? \"flush\" : in_observer ? \"observer\" : \"???\");",
                  $stacks);
        add_probe('pid$pid_SpringBoard:QuartzCore:CA??Transaction??commit*:return', undef, "in_flush = 0;");
    }

}

# TODO: track bootloading! (integrate nhams bootloading dtrace too)
#
# <rdar://problem/9607170> touch unresponsive on lock screen
#
# multitouch bootloading:
# 		thread_call_initialize
# 		IOTimerEventSource::timeoutAndRelease(void*, void*)
# 		AppleMultitouchSPI::bootloadTimerFiredHandler(OSObject*, IOTimerEventSource*)
# 		AppleMultitouchSPI::bootloadDeviceGated()
# 		IOWorkLoop::runAction(int (*)(OSObject*, void*, void*, void*, void*), OSObject*, void*, void*, void*, void*)
#
# 		AppleMultitouchZ2SPI::bootloadDevice()
# 		MTSPIBootloader_Z2::bootloadDevice()
# 		MTSPIBootloader_Z2::sendCalibrationDataBytes()
# 		AppleARMSPIDevice::transferData(IOMemoryDescriptor*, unsigned long, unsigned long, void*, unsigned long, AppleARMSPICompletion*)
# 		AppleARMSPIDevice::transferData(IOMemoryDescriptor*, void*, unsigned long, unsigned long, IOMemoryDescriptor*, void*, unsigned long, unsigned long, AppleARMSPICompletion*)
# 		IOCommandGate::runAction(int (*)(OSObject*, void*, void*, void*, void*), void*, void*, void*, void*)
# 		AppleARMSPIController::enqueueSPICommandGated(AppleARMSPICommand*)
# 		AppleS5L8900XSPIController::setSPIControllerActive(bool)
# 		AppleARMIODevice::enableDeviceClock(unsigned long, unsigned long)
# 		AppleS5L8940XIO::enableDeviceClock(unsigned long, unsigned long)
# 		AppleARMPerformanceControllerFunctionClockGate::callFunction(void*, void*, void*)
# 		AppleARMPerformanceController::enableDeviceClock(unsigned long, unsigned long)
# 		IOCommandGate::runAction(int (*)(OSObject*, void*, void*, void*, void*), void*, void*, void*, void*)
# 		IOEventSource::openGate()
# 		IOWorkLoop::openGate()
#
# 		MTSimpleHIDManager::deviceDidBootload()

sub exec_dtrace {
    my ($fh, $fname) = tempfile(SUFFIX => '.d');
    printf("Generating dtrace script in $fname\n");
    for my $line (@dtrace_script) {
        print $fh "$line\n";
    }
    close($fh);

    my $dtrace_sz = int(`sysctl -n kern.dtrace.dof_maxsize`);
    if ($dtrace_sz < (1024 * 1024)) {
        `sysctl -w kern.dtrace.dof_maxsize=1048575`;
    }

    my $tstamp = strftime("%F-%H-%M-%S", localtime);
    my $outname = "${model_str}_${build}_${tstamp}_dtrace.log";
    printf("Writing dtrace output to $outname\n");
    exec "dtrace -s $fname -o $outname && rm -f $fname && cat /var/mobile/Library/Logs/wake | tail -n 1";
}

main();
