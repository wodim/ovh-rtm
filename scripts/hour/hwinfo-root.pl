#! /usr/bin/perl
# version: 0.9.4 (2011-12-06)

$ENV{"LC_ALL"} = "POSIX";

use strict;

sub send_mainboard_memory_info {
    my %mainboard_memory_info = get_mainboard_memory_info();
    print "dHW_MB_manufacture|" . $mainboard_memory_info{'mainboard'}{'manufacture'} . "\n";
    print "dHW_MB_name|" . $mainboard_memory_info{'mainboard'}{'name'} . "\n";
    foreach (keys %{$mainboard_memory_info{'memory'}}) {
        print "dHW_MEM_BANK-$_|" . $mainboard_memory_info{'memory'}{$_} . "\n";
    }
}

sub send_hdd_info {
    my %hdd_info = get_hdd_info();
    get_hdd_info_scsi(\%hdd_info);
    foreach (keys %{$hdd_info{'model'}}) {
        print "dHW_HDD_$_\_capacity|" . $hdd_info{'capacity'}{$_} . " GB" . "\n";
        print "dHW_HDD_$_\_model|" . $hdd_info{'model'}{$_} . "\n";
    }
}

sub get_mainboard_memory_info {
    my %mainboard_memory_info = ();
    my @dmidecode = `dmidecode 2>/dev/null`;
    if ($? == 0) {
        my $module = "";
        for (my $i = 0; $i < @dmidecode; $i++) {
            if($dmidecode[$i] =~ /^\s*Base Board Information/i) {
                $dmidecode[$i+1] =~ s/Manufacturer://g;
                $dmidecode[$i+2] =~ s/Product Name://g;
                $mainboard_memory_info{'mainboard'}{'manufacture'} = $dmidecode[$i+1];
                $mainboard_memory_info{'mainboard'}{'name'} = $dmidecode[$i+2];
            }
            if($dmidecode[$i] =~ /^\s*Memory Module Information/i) {
                $dmidecode[$i+1] =~ /^\s+(\S+)\s+(\S+)\s+(.+)$/i;
                $module = $3;
                $module =~ s/\W/-/g;
                chomp($module);
            }
            if(($dmidecode[$i] =~ /^\s+Installed Size:/i)  && ($module =~ /\S+/)) {
                $module =~ s/#/_/;
                $dmidecode[$i] =~ s/Installed Size://g;
                $mainboard_memory_info{'memory'}{$module} = $dmidecode[$i];
                $mainboard_memory_info{'memory'}{$module} =~ s/^\s+//;
                chomp($mainboard_memory_info{'memory'}{$module});
                $module = "";
            }
        }
        if (!defined $mainboard_memory_info{'memory'}) {
            for (my $i = 0; $i < @dmidecode; $i++){
                if($dmidecode[$i] =~ /^\s*Memory Device/i) {
                    my $bank = $dmidecode[$i+9];
                    $bank =~ /Bank Locator:\s+(.*)/;
                    $bank = $1;
                    next if !$bank;
                    $bank =~ s/\s//g;
                    $bank =~ s/[\s\.\/\\_]/-/g;
                    my $locator = $dmidecode[$i+8];
                    $locator =~ /Locator:\s+(.*)/;
                    $locator = $1;
                    next if !$locator;
                    $locator =~ s/\s//g;
                    $locator =~ s![\s./\\_#]!-!g;
                    my $size = $dmidecode[$i+5];
                    $size =~ /Size:\s+(.*)/;
                    $size = $1;
                    next if !$size;
                    $size =~ s/\s*MB\s*//g;
                    chomp($size);
                    if ($bank . $locator ne "") {
                        $mainboard_memory_info{'memory'}{$bank . "-" . $locator} = $size;
                    }
                }
            }
        }
        $mainboard_memory_info{'mainboard'}{'manufacture'} =~ s/^\s+//;
        $mainboard_memory_info{'mainboard'}{'name'} =~ s/^\s+//;
        chomp($mainboard_memory_info{'mainboard'}{'manufacture'});
        chomp($mainboard_memory_info{'mainboard'}{'name'});
    } else {
        $mainboard_memory_info{'mainboard'}{'manufacture'} = "dmidecode not installed";
        $mainboard_memory_info{'mainboard'}{'name'} = "dmidecode not installed";
    }
    return %mainboard_memory_info;
}

sub has_raid {
    my $dmesg = `cat /var/log/dmesg`;
    return ((-e "/proc/mdstat" && `grep md /proc/mdstat` ne "") ||
            ($dmesg =~ m/3w-xxxx: scsi/) ||
            (`lspci -d 1000: 2>&1` ne "") ||
            ($dmesg =~ m/scsi. : Found a 3ware/) ||
            ($dmesg =~ m/3w-9xxx: scsi.: Found/) ||
            ($dmesg =~ m/LSISAS1064 A3/) ||
            ($dmesg =~ m/Mylex AcceleRAID 160 PCI RAID Controller/));
}

sub get_scsi_disk_capacity {
    my $device = shift;
    my $capacity = "0";
    open my $FP, "fdisk -l $device |" or return "0";
    while (my $line = <$FP>) {
        next unless $line =~ /^Disk\s+$device:\s+([^,]+)/;
        $capacity = $1;
        $capacity =~ s/\s//g;
        $capacity =~ s/GB$//g;
        last;
    }
    return "0" unless close $FP;
    return $capacity;
}

sub get_hdd_info_scsi {
    return () if has_raid();
    my $hdd_info = shift;
    open my $FP, "/proc/scsi/scsi" or return ();
    chomp(my $scsi = join('', <$FP>));
    close $FP;
    my @letters = ('a'..'z');
    while ($scsi =~ /^\s*Vendor:\s*.+Model:\s*(.+?)\s*Rev:/mg) {
        my $l = shift @letters;
        $hdd_info->{'model'}{"sd$l"} = $1;
        $hdd_info->{'capacity'}{"sd$l"} = get_scsi_disk_capacity("/dev/sd$l");
    }
}

sub get_hdd_info {
    my %hdd_info = ();
    my $ide = `ls /proc/ide`;
    my @ide = split(/\s+/, $ide);
    foreach (@ide) {
        if (/^hd/) {
            $ide = $_;
            if (-e "/proc/ide/$ide/model") {
                open(FILE, "/proc/ide/$ide/model");
                while (<FILE>) {
                    chomp($_);
                    $hdd_info{'model'}{$ide} = $_;
                }
                close(FILE);
            } else {
                $hdd_info{'model'}{$ide} = "";
            }
            if (-e "/proc/ide/$ide/capacity") {
                open(FILE, "/proc/ide/$ide/capacity");
                while (<FILE>) {
                    chomp($_);
                    $hdd_info{'capacity'}{$ide} = sprintf("%d",$_*512/1000000000);
                }
                close(FILE);
            }  else {
                $hdd_info{'capacity'}{$ide} = ""
            };
        }
    }
    return %hdd_info;
}


send_mainboard_memory_info();
send_hdd_info();
