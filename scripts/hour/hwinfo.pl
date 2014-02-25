#! /usr/bin/perl
# version: 0.9.4 (2011-12-06)

$ENV{"LC_ALL"} = "POSIX";

use strict;

sub send_cpu_info {
    my %cpu_info = get_cpu_info();
    print "dHW_CPU_name|" . $cpu_info{'cpu_name'} . "\n";
    print "dHW_CPU_mhz|" . $cpu_info{'cpu_mhz'} . "\n";
    print "dHW_CPU_cache|" . $cpu_info{'cpu_cache'} . "\n";
    print "dHW_CPU_number|" . $cpu_info{'cpu_no'} . "\n";
}

sub send_lspci_info {
    my %lspci_info = get_lspci_info();
    foreach (keys %lspci_info) {
        my $tempKey = $_;
        $tempKey =~ s/\:|\.|\_/-/g;
        print "dHW_LSPCI_PCI-$tempKey|" . $lspci_info{$_} . "\n";
    }
}


sub get_cpu_info {
    my %cpu_info = ( 'cpu_no' => 0 );
    open(CONF,"/proc/cpuinfo") or die "loadavg: $!\n";
    while( <CONF> ) {
        chomp($_);
        if ($_ =~ /^model name\s+:\s(.*)/) {
            $cpu_info{'cpu_name'} = $1;
            $cpu_info{'cpu_no'} += 1;
        }
        if ($_ =~ /^cpu MHz/) {
            s/cpu MHz\s+:\s*//g;
            $cpu_info{'cpu_mhz'} = $_;
        }
        if ($_ =~ /^cache size/) {
            s/cache size\s+:\s*//g;
            $cpu_info{'cpu_cache'} = $_;
        }
    }
    $cpu_info{'cpu_no'} = $cpu_info{'cpu_no'};
    close(CONF);
    return %cpu_info;
}


sub get_lspci_info {
    my %lspci_info = ();
    my @lspci = `lspci -n 2>/dev/null`;
    if ($? == 0) {
        foreach (@lspci) {
            if (/^(\S+).+:\s+(.+:.+)\s+\(/i) {
                $lspci_info{$1} = $2;
            }
            elsif (/^(\S+).+:\s+(.+:.+$)/i){
                $lspci_info{$1} = $2;
            }
        }
    }
    return %lspci_info;
}

send_cpu_info();
send_lspci_info();
