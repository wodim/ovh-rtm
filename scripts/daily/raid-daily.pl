#! /usr/bin/perl
# version: 0.9.4 (2011-12-06)

$ENV{"LC_ALL"} = "POSIX";

use strict;
use IO::Select;

my $dmesg = `cat /var/log/dmesg /var/log/boot.msg 2>/dev/null`;

#3Ware-9xxx
if ( $dmesg =~ m/3w-9xxx: scsi.: Found/) {
    my $MAX_FORKS = 3;

    my $TWCLI = `which tw_cli 2>/dev/null`;
    chomp($TWCLI);
    if ($TWCLI ne "") {
        my @twCliInfo = `$TWCLI info`;
        my @controlers = ();
        foreach my $line (@twCliInfo) {
            push @controlers, $1 if $line =~ /^c(\d+)\s+/;
        }
        foreach my $controler (@controlers) {
            my %units = ();
            @twCliInfo = `$TWCLI info c$controler`;
            foreach my $line (@twCliInfo) {
                if ( $line =~ m/^p(\d)\s+([^\s]+)\s+u([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)/) {
                    push @{$units{$3}}, $1 if $2 ne "NOT-PRESENT";
                }
            }
            foreach my $unit (keys %units) {
                my $read_set = IO::Select->new();
                my $n_forked = 0;
                my @units = @{$units{$unit}};
                while (@units > 0) {
                    my $phys = pop @units;
                    pipe my $P_READ, my $P_WRITE or die "pipe(): $!";
                    my $pid = fork();
                    die "cannot fork: $!" if $pid < 0;
                    if ($pid == 0) {
                        close $P_READ;
                        select($P_WRITE);
                        my $line = `$TWCLI info c$controler p$phys model`;
                        $line =~ m/Model\s=\s(.+)/;
                        print "dHW_SCSIRAID_PORT_c$controler\_u$unit\_phy$phys\_model|$1\n";
                        exit();
                    }
                    close $P_WRITE;
                    $read_set->add($P_READ);

                    ++$n_forked;
                    if ($n_forked > $MAX_FORKS || @units == 0) {
                        while (my @fds = $read_set->can_read()) {
                            foreach my $fd (@fds) {
                                my $line = <$fd>;
                                if (!$line) {
                                    $read_set->remove($fd);
                                    close $fd;
                                } else {
                                    print $line;
                                }
                            }
                        }
                        while (waitpid(-1, 0) > 0) {
                        }
                        $n_forked = 0;
                    }
                }
            }
        }
    }
}
