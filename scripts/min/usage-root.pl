#! /usr/bin/perl
# version: 0.9.4 (2011-12-06)

$ENV{"LC_ALL"} = "POSIX";

use strict;

sub send_process {
    my %processes = get_processes();
    print "mINFO_LOAD_processesactive|" . $processes{'processesactive'} . "\n";
    print "mINFO_LOAD_processesup|" . $processes{'processesup'} . "\n";
}

sub send_top_rss {
    my $top = get_top_mem_procs();
    my $n = 1;
    foreach my $info (@$top) {
        my $vsz = $info->[0];
        my $cmd = $info->[1];
        printf "mINFO_MEM_top_mem_%02d_name|%s\n", $n, $cmd;
        printf "mINFO_MEM_top_mem_%02d_size|%s\n", $n, $vsz;
        ++$n;
    }
}

sub get_processes {
    chomp(my @rtm_sids = `ps --no-headers -C rtm -o sess | sort -n | uniq`);
    my @ps_output = `ps --no-headers -A -o sess,state,command`;
    my $active = 0;
    my $total = 0;
    my $rtm_procs = 0;
    foreach my $line (@ps_output) {
        next if $line !~ /(\d+)\s+(\S+)/;
        my $sid = $1;
        my $state = $2;
        if (grep $sid == $_, @rtm_sids) {
            ++$rtm_procs;
            next;
        }
        ++$total;
        ++$active if $state =~ /^R/;
    }
    return ('processesactive' => $active, 'processesup' => $total);
}

sub get_top_mem_procs {
    my @top;
    my @output = `ps -A -o vsz,cmd --sort=-vsz --no-headers | head -n 5`;
    return [] unless $? == 0;
    foreach (@output) {
        next unless m/\s*(\d+)\s+(.+)/;
        push @top, [$1, $2];
    }
    return \@top;
}

send_process();
send_top_rss();
