#! /usr/bin/perl
# version: 0.9.4 (2011-12-06)

$ENV{"LC_ALL"} = "POSIX";

use strict;
use utf8; # for \x{nnn} regex

my (@netstatTable, $line, $socketInfo, $procInfo, @tempTable, $port, $pid, $procName, $ip, $cmdline, $exe, @status, $statusLine, $uid, @passwd, $passwdLine, %passwdHash);

chomp(@netstatTable = `netstat -tlenp | grep LISTEN | awk '{print \$4"|"\$9}'`);

open(FILE, "/etc/passwd");
chomp(@passwd = <FILE>);
close(FILE);

foreach $passwdLine (@passwd) {
    $passwdLine =~ /^([^:]+):[^:+]:(\d+):/;
    $passwdHash{$2} = $1;
}

foreach $line (@netstatTable) {

    @tempTable = split(/\|/, $line);
    $socketInfo = $tempTable[0];
    $procInfo = $tempTable[1];

    $socketInfo =~ /:(\d+)$/;
    $port = $1;
    $socketInfo =~ /(.+):\d+$/;
    $ip = $1;
    $ip =~ s/\./-/g;
    $ip =~ s/[^0-9\-]//g;
    if ($ip eq "") {$ip = 0;}
    @tempTable = split(/\//, $procInfo);
    $pid = $tempTable[0];
    open(FILE, "/proc/$pid/cmdline");
    chomp($cmdline = <FILE>);
    $cmdline =~ s/\x{0}/ /g;
    close(FILE);

    open(FILE, "/proc/$pid/status");
    chomp(@status = <FILE>);
    close(FILE);
    $statusLine = join("|", @status);
    $statusLine =~ /Uid:\s(\d+)/;
    $uid = $1;

    my $username = '';
    if (defined $passwdHash{$uid}) {
        $username = $passwdHash{$uid};
    }

    $procName = $tempTable[1];
    $exe = readlink("/proc/$pid/exe");

    print "hINFO_TCP_LISTEN_IP-$ip\_PORT-$port\_pid\|$pid\n";
    print "hINFO_TCP_LISTEN_IP-$ip\_PORT-$port\_procname\|$procName\n";
    print "hINFO_TCP_LISTEN_IP-$ip\_PORT-$port\_cmdline\|$cmdline\n";
    print "hINFO_TCP_LISTEN_IP-$ip\_PORT-$port\_exe\|$exe\n";
    print "hINFO_TCP_LISTEN_IP-$ip\_PORT-$port\_username\|$username\n";
    print "hINFO_TCP_LISTEN_IP-$ip\_PORT-$port\_uid\|$uid\n";
}
