#! /usr/bin/perl
# version: 0.9.4 (2011-12-06)

$ENV{"LC_ALL"} = "POSIX";

use strict;

# tmp file for storing cpu stats from /proc/stat
my $CPU_STATS = "/tmp/cpu_stats";

sub send_loadavg {
    my %loadavg = get_loadavg();
    print "mINFO_LOAD_loadavg1|" . $loadavg{'loadavg1'} . "\n";
    print "mINFO_LOAD_loadavg2|" . $loadavg{'loadavg2'} . "\n";
    print "mINFO_LOAD_loadavg3|" . $loadavg{'loadavg3'} . "\n";
}

sub send_mem_swap_usage {
    my %mem_swap_usage = get_mem_swap_usage();
    print "mINFO_MEM_memusage|" . $mem_swap_usage{'mem_used_pr'} . "\n";
    print "mINFO_MEM_swapusage|" . $mem_swap_usage{'swap_used_pr'} . "\n";
}

sub send_cpu_usage {
    my $cpu_usage = get_cpu_usage();
    print "mINFO_CPU_usage|" . $cpu_usage . "\n";
}

sub send_hdd_usage {
    my %hdd_usage = get_hdd_usage();
    foreach (keys %{$hdd_usage{'usage'}}) {
        print "mINFO_PART_$_\_mount|" . $hdd_usage{'mount'}{$_} . "\n";
        print "mINFO_PART_$_\_usage|" . $hdd_usage{'usage'}{$_} . "\n";
        print "mINFO_PART_$_\_inodes|" . $hdd_usage{'inodes'}{$_} . "\n";
    }
}

sub get_loadavg {
    open(CONF, "/proc/loadavg") or die "loadavg: $!\n";
    chomp(my @load = split(/\s/, <CONF>));
    close(CONF);
    return ('loadavg1' => $load[0],
            'loadavg2' => $load[1],
            'loadavg3' => $load[2],);
}

sub get_cpu_usage {
    my ($cpu_usage, @cpu_usage1, @cpu_usage2, $delta);
    @cpu_usage1 = (0, 0, 0, 0);
    @cpu_usage2 = (0, 0, 0, 0);


    open(STAT, "/proc/stat") or die "/proc/stat: $!\n";
    my @stats = <STAT>;
    close (STAT);

    foreach (@stats) {
        if (/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/i) {
            @cpu_usage2 = ($1, $2, $3, $4);
        }
    }

    # it can happen after reboot
    if( ! -e $CPU_STATS) {
       open(TMP, ">$CPU_STATS") or die "$CPU_STATS: $!\n";
       print TMP @stats;
       close(TMP);
       return 0;
    }

    open(TMP, '+<', $CPU_STATS) or die "$CPU_STATS: $!\n";
    while (<TMP>) {
        if (/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/i) {
            @cpu_usage1 = ($1, $2, $3, $4);
        }
    }
    seek(TMP, 0, 0);
    print TMP @stats;
    close (TMP);

    $delta = $cpu_usage2[0]+$cpu_usage2[1]+$cpu_usage2[2]+$cpu_usage2[3]-
        ($cpu_usage1[0]+$cpu_usage1[1]+$cpu_usage1[2]+$cpu_usage1[3]);
    if ($delta > 0) {
        $cpu_usage = sprintf("%d", 100-(($cpu_usage2[3]-$cpu_usage1[3])/$delta*100));
    } else {
        $cpu_usage = 0;
    }
    return $cpu_usage;
}

sub get_mem_swap_usage {
    my %mem_swap_usage = ();
    my @free = `free`;
    foreach (@free) {
        if (/^Swap:\s+(\d+)\s+(\d+)\s+(\d+)/i) {
            $mem_swap_usage{'swap_total'} = $1;
            $mem_swap_usage{'swap_used'} = $2;
            if ($1 == 0) {
                # prevent division by zero
                $mem_swap_usage{'swap_used_pr'} = 0;
            } else {
                $mem_swap_usage{'swap_used_pr'} = sprintf("%d", $2/$1*100);
            }
        }
        if (/^Mem:\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/i) {
            $mem_swap_usage{'mem_total'} = $1;
            $mem_swap_usage{'mem_used'} = $2;
            $mem_swap_usage{'mem_free'} = $3;
            $mem_swap_usage{'mem_shared'} = $4;
            $mem_swap_usage{'mem_buffers'} = $5;
            $mem_swap_usage{'mem_cached'} = $6;
            $mem_swap_usage{'mem_used_pr'} = sprintf("%d", (($2-$5-$6)/$1*100));
        }
    }
    return %mem_swap_usage;
}

sub get_hdd_usage {
    my %hdd_usage = ();
    my @df = `df -l`;
    foreach (@df){
        if (/^(\/dev\/\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\S+)\s+(\S+)/i) {
            my $hdd_name = $1;
            my $hdd_usage = $5;
            my $hdd_mount = $6;
            $hdd_name =~ s!^/dev/!!g;
            $hdd_name =~ s!/!-!g;
            $hdd_usage{'usage'}{$hdd_name} = $hdd_usage;
            $hdd_usage{'usage'}{$hdd_name} =~ s/%//;
            $hdd_usage{'mount'}{$hdd_name} = $hdd_mount;
        }
    }

    # inodes
    @df = `df -li`;
    foreach (@df) {
        if (/^(\/dev\/\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\S+)\s+(\S+)/i) {
            my $hdd_name = $1;
            my $hdd_usage = $5;
            $hdd_usage =~ s/%//;
            $hdd_usage = 0 unless $hdd_usage =~ /^\d+$/;
            $hdd_name =~ s/^\/dev\///g;
            $hdd_name =~ s!/!-!g;
            $hdd_usage{'inodes'}{$hdd_name} = $hdd_usage;
        }
    }
    return %hdd_usage;
}

send_hdd_usage();
send_mem_swap_usage();
send_loadavg();
send_cpu_usage();
