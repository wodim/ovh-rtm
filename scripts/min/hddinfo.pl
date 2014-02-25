#! /usr/bin/perl
# version: 0.9.4 (2011-12-06)

$ENV{"LC_ALL"} = "POSIX";

use strict;

sub send_hdd_status {
    chomp(my $ide = `ls /proc/ide`);
    chomp(my @status = `\/bin\/dmesg \| grep -i \"error\\\|drive not ready\" \| grep -i \"\^hd\" \| cut -f 1 -d \":\" \| sort \| uniq`);
    my @ide = split(/\s+/, $ide);
    foreach $ide (@ide) {
        my $error = 0;
        if ($ide =~ /^hd/) {
            foreach (@status) {
                $error = 1 if $_ eq $ide;
            }
            if ($error == 1) {
                print "mHW_HDD_$ide\_status|ERROR\n";
            } else {
                print "mHW_HDD_$ide\_status|OK\n";
            }
        }
    }

    # check of scsi errors
    my $scsi_available = `grep '^Host:' /proc/scsi/scsi 2>/dev/null`;
    my $possible_error;
    if ($scsi_available) {
        open my $dmesg, "dmesg |" or die "Can't launch dmesg: $!";
        my $status = 'OK';
        while (<$dmesg>) {
            if (/Info fld=([^,]+), Deferred (\S+?): sense key (.+ Error)/) {
                $status = $3;
            }
            if (/^sd.: .+?: sense key: (.+ Error)/) {
                $status = $1;
            }
            if (/^(sd.+?): *rw=\d+/) {
                $possible_error = $1;
                next;
            }
            if (defined($possible_error) && /^attempt to access beyond/) {
                $status = 'BAD_ACCESS';
            }
            $possible_error = undef;
        }
        print "mHW_HDD_scsi_status|$status\n";
    }
}

sub send_hdd_temp {
    my %hdd_temp = get_hdd_temp();
    foreach (keys %hdd_temp) {
        print "mINFO_HDD_$_\_temperature|" . $hdd_temp{$_} . "\n";
    }
}


sub get_hdd_temp {
    my %hdd_temp = ();
    my $ide = `ls /proc/ide`;
    my @ide = split(/\s+/, $ide);
    foreach (@ide) {
        if (/^hd/) {
            $ide = $_;
            my $temp = `hddtemp /dev/$ide 2>/dev/null`;
            if ($? == 0) {
                if ($temp =~ m/.*:.*:\s(\d+)/) {
                    $temp = $1;
                } else {
                    $temp = "-1";
                }
                $hdd_temp{$ide} = $temp;
            } else {
                $hdd_temp{$ide} = "-2";
            }
        }
    }
    return %hdd_temp;
}


send_hdd_status();
send_hdd_temp();
