#! /usr/bin/perl
# version: 0.9.4 (2011-12-06)

$ENV{"LC_ALL"} = "POSIX";

use strict;
use IO::Select;

my %smartData;

sub parse_smartctl_line {
    my $line = shift;
    my $dev = shift;
        my $other_errors = 0;

    if ($line =~ /^196 Reallocated_Event_Count.*\s+(\d+)$/) {
        print "hINFO_HDD_$dev\_SMART_realocated-event-count|$1\n";
    }
    if ($line =~ /^197 Current_Pending_Sector.*\s+(\d+)$/) {
        print "hINFO_HDD_$dev\_SMART_current-pending-sector|$1\n";
    }
    if ($line =~ /^198 Offline_Uncorrectable.*\s+(\d+)$/) {
        print "hINFO_HDD_$dev\_SMART_offline-uncorrectable|$1\n";
    }
    if ($line =~ /^199 UDMA_CRC_Error_Count.*\s+(\d+)$/) {
        print "hINFO_HDD_$dev\_SMART_udma-crc-error|$1\n";
    }
    if ($line =~ /^200 Multi_Zone_Error_Rate.*\s+(\d+)$/) {
        print "hINFO_HDD_$dev\_SMART_multizone-error-rate|$1\n";
    }
    if ($line =~ /^209 Offline_Seek_Performnce.*\s+(\d+)$/) {
        print "hINFO_HDD_$dev\_SMART_offline-seek-performance|$1\n";
    }
    if ($line =~ m/^194 Temperature_Celsius .*\s+(\d+)(\s+\([\w\s\/]+\))?$/) {
        print "hINFO_HDD_$dev\_SMART_temperature-celsius|$1\n";
    }

    if ($line =~ /Error \d+ (occurred )?at /){
        $other_errors = 1;
    }

    return (other_errors=>$other_errors);
}

sub check_ide {
    opendir(DIR,"/proc/ide") or return;
    my @diskList = readdir(DIR);
    closedir(DIR);
    foreach my $dev (@diskList) {
        next unless $dev =~ /^hd.$/;
        my $smart_other_error = 0;
        my @smartctlData = `smartctl -a /dev/$dev`;
        foreach my $line (@smartctlData) {
            my %ret = parse_smartctl_line($line, $dev);
            $smart_other_error = 1 if $ret{other_errors};
        }
        print "hINFO_HDD_$dev\_SMART_other-errors|".int($smart_other_error)."\n";
    }
}

sub check_scsi {
    open PART, "/proc/partitions" or return;
    my @disks = ();
    while (<PART>) {
        chomp;
        next unless /\b(sd\D+)\b/;
        push @disks, $1;
    }
    close PART;
    return unless @disks > 0;

    foreach my $dev (@disks) {
        my @smartctlData = `smartctl -a /dev/$dev`;
        my $smart_other_error = 0;
        foreach my $line (@smartctlData) {
            my %ret = parse_smartctl_line($line, $dev);
            $smart_other_error = 1 if $ret{other_errors};

            if ($line =~ /^read:.+(\d+)$/) {
                print "hINFO_HDD_$dev\_SMART_uncorrected-read-errors|$1\n";
            }
            if ($line =~ /^write:.+(\d+)$/) {
                print "hINFO_HDD_$dev\_SMART_uncorrected-write-errors|$1\n";
            }
        }
        print "hINFO_HDD_$dev\_SMART_other-errors|".int($smart_other_error)."\n";
    }
}

sub _3ware_get_ports_for_disk {
    my $disk = shift;
    my @ports = ();
    open my $TWCLI_OUTPUT, "tw_cli info c$disk |" or die("failed to run 'tw_cli'");
    while (<$TWCLI_OUTPUT>) {
        next unless /^p(\d+) /;
        push @ports, $1;
    }
    close $TWCLI_OUTPUT;
    return @ports;
}

sub check_3ware {
    opendir(DIR,"/proc/scsi/3w-9xxx") or return;
    my @disk_list = readdir(DIR);
    closedir(DIR);

    my $read_set = IO::Select->new();

    foreach my $disk (@disk_list) {
        next unless $disk =~ /^\d+$/;
        foreach my $port (_3ware_get_ports_for_disk($disk)) {
            pipe my $P_READ, my $P_WRITE or die "pipe(): $!";
            my $pid = fork();
            die "cannot fork: $!" if $pid < 0;
            if ($pid == 0) {
                open my $SMARTCTL_OUTPUT, "smartctl --device=3ware,$port /dev/twa$disk -a |" or die("failed to run smartctl");
                close $P_READ;
                select($P_WRITE);
                while (<$SMARTCTL_OUTPUT>) {
                    parse_smartctl_line($_, "twa$disk-$port");
                }
                exit();
            }
            close $P_WRITE;
            $read_set->add($P_READ);
        }
    }
    while (my @fds = $read_set->can_read()) {
        foreach my $fd (@fds) {
            my @lines = <$fd>;
            if (!@lines) {
                close $fd;
                next;
            }
            print join('', @lines);
        }
    }
    while (waitpid(-1, 0) > 0) {
    }
}


check_ide();
check_scsi();
check_3ware();
