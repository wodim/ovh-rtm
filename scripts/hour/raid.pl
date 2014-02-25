#! /usr/bin/perl
# version: 0.9.4 (2011-12-06)

$ENV{"LC_ALL"} = "POSIX";

use strict;
use IO::Select;

chomp(my $MDADM=`which mdadm 2>/dev/null`);
chomp(my $MPTSTATUS = `which mpt-status 2>/dev/null`);
chomp(my $LSIUTIL = `which lsiutil 2>/dev/null`);
if($LSIUTIL eq '' and -e "/usr/local/rtm/bin/lsiutil"){
    $LSIUTIL = "/usr/local/rtm/bin/lsiutil";
  }
chomp(my $LSPCI = `which lspci 2>/dev/null`);


if ($LSPCI && `$LSPCI -d 1000:` && $MPTSTATUS) {
    my $SCSI_ID = `$MPTSTATUS -p 2>/dev/null | grep "Found SCSI" | cut -f1 -d, | cut -f2 -d=`;
    if ($SCSI_ID eq ""){
        $SCSI_ID = `cat /proc/scsi/scsi 2>/dev/null | grep Host | tail -n 1 | cut -d ' ' -f6`;
    }
    chomp $SCSI_ID;
    if ($SCSI_ID ne "") { $MPTSTATUS = "$MPTSTATUS -i $SCSI_ID"; }
} else {
    undef $MPTSTATUS;
}

my $dmesg = `cat /var/log/dmesg /var/log/boot.msg 2>/dev/null`;
my ($line, @mptInfo, @twCliInfo, $controler);

#SOFT RAID
my $mdstat;
if ( $MDADM ne "" && -e "/proc/mdstat" && `cat /proc/mdstat | grep md` ne "") {
    open(FILE, "/proc/mdstat");
    my $matrix;
    foreach $line (<FILE>) {
        if ( $line =~ /(md\d+)\s+:\s+([^\s]+)\s+([^\s]+)/ ) {
            $matrix = $1;
            $mdstat->{$matrix}{status}  = $2;
            $mdstat->{$matrix}{type}    = $3;
        }
        if ( $line =~ /\s+(\d+)/ ) {
            $mdstat->{$matrix}{capacity}    = $1;
        }
    }
    close(FILE);
    foreach $matrix (keys %{$mdstat}) {
        open(IN, "$MDADM -D /dev/$matrix |");
        foreach $line (<IN>) {
            if ( $line =~ /\s+\d+\s+\d+\s+\d+\s+(\d+)\s+(\w+)\s+(\w+)\s+\/dev\/(\w+)/ ) {
                $mdstat->{$matrix}{device}{$1}{state} = $2;
                $mdstat->{$matrix}{device}{$1}{flags} = $3;
                $mdstat->{$matrix}{device}{$1}{drive} = $4;
            }
            if ( $line =~ /^\s+State\s+:\s+([^\s]+)/ ) {
                $mdstat->{$matrix}{state}   = $1;
            }
        }
        close(IN);

        print "hHW_SCSIRAID_UNIT_$matrix\_vol0_capacity|".sprintf("%.1f", $mdstat->{$matrix}{capacity}/1024/1024)." GB\n";
        print "hHW_SCSIRAID_UNIT_$matrix\_vol0_phys|".(keys %{$mdstat})."\n";
        print "hHW_SCSIRAID_UNIT_$matrix\_vol0_type|$mdstat->{$matrix}{type}\n";
        print "hHW_SCSIRAID_UNIT_$matrix\_vol0_status|$mdstat->{$matrix}{status}\n";
        print "hHW_SCSIRAID_UNIT_$matrix\_vol0_flags|$mdstat->{$matrix}{state}\n";

        open(FILE, "/proc/partitions");
        my @file = <FILE>;
        close(FILE);
        foreach my $device (keys %{$mdstat->{$matrix}{device}}) {
            foreach $line (@file) {
                if ( $line =~ /\s+\d+\s+\d+\s+(\d+)\s+$mdstat->{$matrix}{device}{$device}{drive}/ ) {
                    $mdstat->{$matrix}{device}{$device}{capacity} = $1;
                }
            }
            print "hHW_SCSIRAID_PORT_$matrix\_vol0\_$mdstat->{$matrix}{device}{$device}{drive}\_capacity|".sprintf("%.1f", $mdstat->{$matrix}{device}{$device}{capacity}/1024/1024)." GB\n";
            print "hHW_SCSIRAID_PORT_$matrix\_vol0\_$mdstat->{$matrix}{device}{$device}{drive}\_status|$mdstat->{$matrix}{device}{$device}{state}\n";
            print "hHW_SCSIRAID_PORT_$matrix\_vol0\_$mdstat->{$matrix}{device}{$device}{drive}\_flags|$mdstat->{$matrix}{device}{$device}{flags}\n";
        }
    }
}


#SCSI-RAID
if ($MPTSTATUS and not $LSIUTIL) {
    my %mptStat;
    @mptInfo = `$MPTSTATUS 2>/dev/null`;
    foreach $line (@mptInfo) {
        if ( $line =~ m/(^[^\s]+)\s+([^\s]+)\s+(\d+)\s+type\s+([^,]+),\s+(\d+)\s+phy,\s+(\d+)\s+GB,\s+flags\s+([^,]+),\s+state\s+(.+)/) {
            $mptStat{cntrl} = $1;
            $mptStat{vol}   = "$2$3";
            $mptStat{cap}   = $6;
            $mptStat{phys}  = $5;
            $mptStat{type}  = $4;
            $mptStat{flags} = $7;
            $mptStat{status}= $8;
            $mptStat{vol}   =~ s/\_/-/g;
            print "hHW_SCSIRAID_UNIT_$mptStat{cntrl}\_$mptStat{vol}\_capacity|$mptStat{cap} GB\n";
            print "hHW_SCSIRAID_UNIT_$mptStat{cntrl}\_$mptStat{vol}\_phys|$mptStat{phys}\n";
            print "hHW_SCSIRAID_UNIT_$mptStat{cntrl}\_$mptStat{vol}\_type|$mptStat{type}\n";
            print "hHW_SCSIRAID_UNIT_$mptStat{cntrl}\_$mptStat{vol}\_status|$mptStat{status}\n";
            print "hHW_SCSIRAID_UNIT_$mptStat{cntrl}\_$mptStat{vol}\_flags|$mptStat{flags}\n";
            next;
        } elsif ( $line =~ m/(^[^\s]+)\s+([^\s]+)\s+(\d+)\s+type\s+([^,]+),\s+(\d+)\s+phy,\s+(\d+)\s+GB,\s+state\s+(.+),\s+flags\s+([^,]+)\n/) {
            $mptStat{cntrl} = $1;
            $mptStat{vol}   = "$2$3";
            $mptStat{cap}   = $6;
            $mptStat{phys}  = $5;
            $mptStat{type}  = $4;
            $mptStat{status}= $7;
            $mptStat{flags} = $8;
            $mptStat{vol}   =~ s/\_/-/g;
            print "hHW_SCSIRAID_UNIT_$mptStat{cntrl}\_$mptStat{vol}\_capacity|$mptStat{cap} GB\n";
            print "hHW_SCSIRAID_UNIT_$mptStat{cntrl}\_$mptStat{vol}\_phys|$mptStat{phys}\n";
            print "hHW_SCSIRAID_UNIT_$mptStat{cntrl}\_$mptStat{vol}\_type|$mptStat{type}\n";
            print "hHW_SCSIRAID_UNIT_$mptStat{cntrl}\_$mptStat{vol}\_status|$mptStat{status}\n";
            print "hHW_SCSIRAID_UNIT_$mptStat{cntrl}\_$mptStat{vol}\_flags|$mptStat{flags}\n";
            next;
        }
        if ( $line =~ m/(^[^\s]+)\s+([^\s]+)\s+(\d+)\s+scsi_id\s+\d+\s+([^\s]+)\s+([^\s]+)[^,]+,\s+(\d+)[^,]+,\s+state\s+(.+), flags\s+(.+)/ ) {
            next if $6 == 0;        # ignore fake raid entries
            print "hHW_SCSIRAID_PORT_$1_$mptStat{vol}\_$2$3_capacity|$6 GB\n";
            print "hHW_SCSIRAID_PORT_$1_$mptStat{vol}\_$2$3_model|$4 $5\n";
            print "hHW_SCSIRAID_PORT_$1_$mptStat{vol}\_$2$3_status|$7\n";
            print "hHW_SCSIRAID_PORT_$1_$mptStat{vol}\_$2$3_flags|$8\n";
        } elsif ( $line =~ m/(^[^\s]+)\s+([^\s]+)\s+(\d+)\s+([^\s]+)\s+([^\s]+)[^,]+,\s+(\d+)[^,]+,\s+state\s+(.+)/ ) {
            next if $6 == 0;
            print "dHW_SCSIRAID_PORT_$1_$mptStat{vol}\_$2$3_capacity|$6 GB\n";
            print "dHW_SCSIRAID_PORT_$1_$mptStat{vol}\_$2$3_model|$4 $5\n";
            print "dHW_SCSIRAID_PORT_$1_$mptStat{vol}\_$2$3_status|$7\n";
        } elsif ( $line =~ m/(^[^\s]+)\s+([^\s]+)\s+(\d+)\s+([^\s]+)\s+([^\s]+)[^,]+,\s+(\d+)[^,]+,\s+state\s+(.+), flags\s+(.+)/ ) {
            next if $6 == 0;
            print "hHW_SCSIRAID_PORT_$1_$mptStat{vol}\_$2$3_capacity|$6 GB\n";
            print "hHW_SCSIRAID_PORT_$1_$mptStat{vol}\_$2$3_model|$4 $5\n";
            print "hHW_SCSIRAID_PORT_$1_$mptStat{vol}\_$2$3_status|$7\n";
            print "hHW_SCSIRAID_PORT_$1_$mptStat{vol}\_$2$3_flags|$8\n";
        } elsif ( $line =~ m/(^[^\s]+)\s+([^\s]+)\s+(\d+)\s+([^\s]+)\s+([^\s]+)[^,]+,\s+(\d+)[^,]+,\s+flags\s+([^,]+),\s+state\s+(.+)/ ) {
            next if $6 == 0;
            print "hHW_SCSIRAID_PORT_$1_$mptStat{vol}\_$2$3_capacity|$6 GB\n";
            print "hHW_SCSIRAID_PORT_$1_$mptStat{vol}\_$2$3_model|$4 $5\n";
            print "hHW_SCSIRAID_PORT_$1_$mptStat{vol}\_$2$3_status|$8\n";
            print "hHW_SCSIRAID_PORT_$1_$mptStat{vol}\_$2$3_flags|$7\n";
        }
    }
}

# LSI:
if($LSIUTIL) {
  my %data;
  chomp(my @devs = `cat /proc/mpt/summary`);

  # foreach ioc device:
  foreach (@devs){
    m/^(.*?):.*Ports=(\d+),/;
    my ($unit, $ports) = ($1, $2);

    # foreach ports:
    for (my $port=1; $port <= $ports; $port++){
      chomp(my @diskDetails = `$LSIUTIL -p$port -a 21,2,0,0,0`);
      chomp(my @LSIRES = `$LSIUTIL -p$port -a 21,1,0,0,0`);

      # each line:
      my ($vol, $bus, $target, $type);
      $vol = -1;
      foreach my $line (@LSIRES){
        #Volume 0 is Bus 0 Target 2, Type IM (Integrated Mirroring)
        if($line =~ /^Volume (\d+) is Bus (\d+) Target (\d+), Type (\w+) /) {
          ($vol, $bus, $target, $type) = ($1, $2, $3, $4);
          $data{$unit}{$port}{$vol}{$bus}{$target}{type} = $type;
          # Warning: $target is a scsi id (vol_id$target) in RTM
        }
        # skip all till Volume.. line
        next if $vol == -1;

        #  Volume State:  optimal, enabled
        if($line =~ /Volume State:  (.+?), (.*)$/) {
          $data{$unit}{$port}{$vol}{$bus}{$target}{status} = uc $1;
          $data{$unit}{$port}{$vol}{$bus}{$target}{flags} = uc $2;
          if($2 =~ /resync in progress/i){
            chomp(my @lsitmp = `$LSIUTIL -p$port -a 21,3,0,0,0`);
            my $checkNextLine = 0;
            foreach(@lsitmp){
              # Resync Progress:  total blocks 4394526720, blocks remaining 3298477568, 75%
              if($checkNextLine and /^\s*Resync Progress:.*?,\s*(\d+)%\s*/){
                $data{$unit}{$port}{$vol}{$bus}{$target}{syncprogress} = $1;
              }
              next unless /Volume $vol State:/i;
              $checkNextLine = 1;
            }
          }
        }

        #Volume Size 417708 MB, Stripe Size 64 KB, 6 Members
        if($line =~ /Volume Size (\d+ \w+), Stripe Size (\d+ \w+), (\d+) Members/){
          $data{$unit}{$port}{$vol}{$bus}{$target}{capacity} = $1;
          $data{$unit}{$port}{$vol}{$bus}{$target}{stripe} = $2; # NEW
          $data{$unit}{$port}{$vol}{$bus}{$target}{phys} = $3;
        }elsif($line =~ /Volume Size (\d+ \w+), (\d+) Members/){
        #Volume Size 417708 MB, 2 Members
          $data{$unit}{$port}{$vol}{$bus}{$target}{capacity} = $1;
          $data{$unit}{$port}{$vol}{$bus}{$target}{phys} = $2;
        }

        if($line =~ /is PhysDisk (\d+)/){
          my %disk;
          $disk{nr} = $1;

          # now we know which disk is here, so find it:
          my $stop = 0;
          foreach(@diskDetails) {
            $stop = 1 and next
              if(/PhysDisk $disk{nr} is Bus/);
              #PhysDisk 0 is Bus 0 Target 3

            next unless $stop;

            #PhysDisk State:  online
            if(/PhysDisk State: (.*)/){
              $disk{status} = uc $1;
              $disk{status} =~ s/^\s+|\s+$//g;
            }
            
            #PhysDisk Size 238475 MB, Inquiry Data:  ATA      ST3250410AS      A
            if(/PhysDisk Size (\d+ \w+), Inquiry Data:\s+(.*)/){
              $disk{capacity} = $1;
              $disk{model} = $2;
              $disk{model} =~ s/\s+/ /g;
              $disk{model} =~ s/^\s+|\s+$//g;
              $disk{model} =~ s/(\w+ \w+) \w+/\1/g; # delete rev, for backward compatibility
            }

           # fix for 2 SSD IM sizes
            if( $data{$unit}{$port}{$vol}{$bus}{$target}{type} eq 'IM'
                and $data{$unit}{$port}{$vol}{$bus}{$target}{phys} == 2
                and $disk{capacity} > $data{$unit}{$port}{$vol}{$bus}{$target}{capacity} * 1.01 ){
              my $old_model = $disk{model};
              my $d = scan4LsiDisks($port);
              my $new_model = $d->{$disk{nr}}{model};
              $new_model =~ s/\s+/ /g;
              $new_model =~ s/^\s+|\s+$//g;
              $new_model = $d->{$disk{nr}}{vendor} . ' ' . $new_model;
              if($old_model ne $new_model){
                $disk{model} = $new_model;
                $disk{capacity} = $data{$unit}{$port}{$vol}{$bus}{$target}{capacity}; # ugly
              }
            }

          }
          push @{$data{$unit}{$port}{$vol}{$bus}{$target}{disks}}, \%disk;
        }
      }
    }
  }

  #@{$data{$unit}{$port}{$vol}{$bus}{$target}{disks}}
  foreach my $unit (keys %data){
    foreach my $port (keys %{$data{$unit}}){
       foreach my $vol (keys %{$data{$unit}{$port}}){
          foreach my $bus (keys %{$data{$unit}{$port}{$vol}}){
            foreach my $target (keys %{$data{$unit}{$port}{$vol}{$bus}}){
              foreach my $key (keys %{$data{$unit}{$port}{$vol}{$bus}{$target}}){
                if($key eq 'capacity'){
                  print "hHW_SCSIRAID_UNIT_$unit\_vol-id$vol\_$key|".changeSizeUnit($data{$unit}{$port}{$vol}{$bus}{$target}{$key})."\n";
                } elsif($key eq 'disks') {
                  foreach my $d (@{$data{$unit}{$port}{$vol}{$bus}{$target}{$key}}){
                      next unless $d->{status};
                      print "hHW_SCSIRAID_PORT_$unit\_vol-id$vol\_phy".$d->{nr}."\_model|".$d->{model}."\n";
                      print "hHW_SCSIRAID_PORT_$unit\_vol-id$vol\_phy".$d->{nr}."\_capacity|".changeSizeUnit($d->{capacity})."\n";
                      print "hHW_SCSIRAID_PORT_$unit\_vol-id$vol\_phy".$d->{nr}."\_status|".$d->{status}."\n";
                      # TODO: no idea from where get the disk flags
                      print "hHW_SCSIRAID_PORT_$unit\_vol-id$vol\_phy".$d->{nr}."\_flags|".(($d->{flags})?$d->{flags}:"NONE")."\n";
                  }
                } else {
                  print "hHW_SCSIRAID_UNIT_$unit\_vol-id$vol\_$key|$data{$unit}{$port}{$vol}{$bus}{$target}{$key}\n";
                }
              }
            }
          }
       }
    }
  }
}

#3Ware
if (( $dmesg =~ m/3w-xxxx: scsi/) || ( $dmesg =~ m/scsi. : Found a 3ware/)) {
    my (%units, @controlers);

    my $TWCLI = `which tw_cli 2>/dev/null`;
    chomp($TWCLI);
    if ($TWCLI ne "") {
        @twCliInfo = `$TWCLI info`;
        foreach $line (@twCliInfo) {
            if ($line =~ m/Controller (\d+):/ || $line =~ /^c(\d+).*$/)  { push @controlers, $1;}
        }
        foreach $controler (@controlers) {
            @twCliInfo = `$TWCLI info c$controler`;
            foreach $line (@twCliInfo) {
                if ( $line =~ m/Unit\s(\d):\s+(RAID\s+\d+|[^\s]+)\s([^\s]+)\s([^\s]+)[^:]+:\s(.+)/) {
                    print "hHW_SCSIRAID_UNIT_c$controler\_u$1_capacity|$3 $4\n";
                    print "hHW_SCSIRAID_UNIT_c$controler\_u$1_type|$2\n";
                    print "hHW_SCSIRAID_UNIT_c$controler\_u$1_status|$5\n";
                }
                if ( $line =~ m/Port\s(\d+):\s([^\s]+)\s([^\s]+)\s([^\s]+)\s([^\s]+)\s([^\s]+)[^:]+:\s([^\(]+)\(unit\s(\d+)/) {
                    print "hHW_SCSIRAID_PORT_c$controler\_u$8_phy$1_capacity|$5 $6\n";
                    print "hHW_SCSIRAID_PORT_c$controler\_u$8_phy$1_model|$2 $3\n";
                    print "hHW_SCSIRAID_PORT_c$controler\_u$8_phy$1_status|$7\n";
                    if (! exists $units{$controler}{$8}) {$units{$controler}{$8} = 0;}
                    $units{$controler}{$8} = $units{$controler}{$8} + 1;
                }
                if (  $line =~ /^u(\d+)\s+(RAID\-\d+)\s+(\S+)\s+\S+\s+\S+\s+(\S+)\s.*/ )
                {
                    print "hHW_SCSIRAID_UNIT_c$controler\_u$1_capacity|$4 GB\n";
                    print "hHW_SCSIRAID_UNIT_c$controler\_u$1_type|$2\n";
                    print "hHW_SCSIRAID_UNIT_c$controler\_u$1_status|$3\n";
                }
                if ( $line =~ /^p(\d+)\s+(\S+)\s+(\S+)\s+(\S+\s\S+)\s+(\d+)\s+(\S+)\s*$/ )
                {
                    print "hHW_SCSIRAID_PORT_c$controler\_$3_phy$1_capacity|$4\n";
                    print "hHW_SCSIRAID_PORT_c$controler\_$3_phy$1_model|$6\n";
                    print "hHW_SCSIRAID_PORT_c$controler\_$3_phy$1_status|$2\n";
                    if (! exists $units{$controler}{$3}) {$units{$controler}{$3} = 0;}
                    $units{$controler}{$3} = $units{$controler}{$3} + 1;
                }
            }
            foreach (keys %{$units{$controler}}) {print "hHW_SCSIRAID_UNIT_c$controler\_$_\_phys|".($units{$controler}{$_})."\n";}
        }
    }
}


#3Ware-9xxx
if ( $dmesg =~ m/3w-9xxx: scsi.: Found/) {
    if (open my $FP, "tw_cli info |") {
        my (%units, @controlers);
        while (my $line = <$FP>) {
            if ($line =~ m/^c(\d+)\s+/) {push @controlers, $1;}
        }
        close $FP;
        foreach $controler (@controlers) {
            open my $FP, "tw_cli info c$controler |" or next;
            while (my $line = <$FP>) {
                if ( $line =~ m/^u(\d)\s+([A-Z0-9\-]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+/ ) {
                    print "hHW_SCSIRAID_UNIT_c$controler\_u$1_capacity|$6\n";
                    print "hHW_SCSIRAID_UNIT_c$controler\_u$1_type|$2\n";
                    print "hHW_SCSIRAID_UNIT_c$controler\_u$1_status|$3\n";
                }
                if ( $line =~ m/^p(\d)\s+([^\s]+)\s+u([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)/) {
                    print "hHW_SCSIRAID_PORT_c$controler\_u$3_phy$1_capacity|$4 $5\n";
                    print "hHW_SCSIRAID_PORT_c$controler\_u$3_phy$1_status|$2\n";
                    push @{$units{$3}}, $1 if ($2 ne "NOT-PRESENT");
                }
            }
            foreach my $unit (keys %units) {
                print "hHW_SCSIRAID_UNIT_c$controler\_u$unit\_phys|".(scalar @{$units{$unit}})."\n";
            }
            close $FP;
        }
    }
}

#Mylex
if ( $dmesg =~ m/Mylex AcceleRAID 160 PCI RAID Controller/) {
    my( @dirContents, $dirContent, @info, $line, $unit, $i, $sectorSize, $count);
    if ( ! -e "/proc/rd") {exit;}
    $count = 0;
    opendir(DIR,"/proc/rd");
    @dirContents=readdir(DIR);
    closedir(DIR);

    $unit = 0;
    foreach $dirContent (@dirContents) {
        if (( $dirContent =~ m/\./ ) || (! -d "/proc/rd/".$controler )) {next;}
        $controler = $dirContent;
        $controler =~ s/c//g;
        open(FILE, "/proc/rd/c$controler/current_status") or exit;
        @info = <FILE>;
        close(FILE);

        for ($i=-1; $i<=scalar @info; $i++) {
            $line = $info[$i];
            chomp($line);
            if ( $line =~ m/\/dev\/rd\/c(\d+)d(\d+):\s+([^,]+),\s+([^,]+),\s+(\d+)/ ) {
                my $capacity = $5;
                my $type = $3;
                my $status = $4;

                $capacity = $capacity * 512 / 1024 / 1024 / 1024;
                print "hHW_SCSIRAID_UNIT_c$controler\_u$unit\_capacity|".sprintf("%.2f",$capacity)." GB\n";
                print "hHW_SCSIRAID_UNIT_c$controler\_u$unit\_type|$type\n";
                print "hHW_SCSIRAID_UNIT_c$controler\_u$unit\_status|$status\n";
            }
            if ( $line =~ m/\s+(\d+):(\d+)\s+Vendor:\s+([^\s]+)\s+Model:\s+([^\s]+)/ ) {
                my $unit = $1;
                my $phys = $2;
                my $vendor = $3;
                my $model = $4;
                next if $model eq 'AcceleRAID'; # it's the controller, not disk
                $count++;
                $line = @info[$i+3];
                $line =~ /Disk Status:\s+([^,]+),\s+(\d+)\sblocks/;

                my $status = $1;
                my $capacity = $2 * 512 / 1024 / 1024 / 1024;

                print "hHW_SCSIRAID_PORT_c$controler\_u$unit\_phy$phys\_capacity|".sprintf("%.2f",$capacity)." GB\n" if ($status ne "0");
                print "hHW_SCSIRAID_PORT_c$controler\_u$unit\_phy$phys\_status|$status\n" if ($status ne "0");
                print "hHW_SCSIRAID_PORT_c$controler\_u$unit\_phy$phys\_model|$model\n";
            }
        }
        print "hHW_SCSIRAID_UNIT_c$controler\_u$unit\_phys|$count\n";
    }
}

# sub to normalize units
sub changeSizeUnit {
  my $str = shift || return;

  $str =~ /^(\d+) (\w+)$/
    and $1 > 1024
    and uc $2 eq 'KB'
    and return int($1/1024)." MB";


  $str =~ /^(\d+) (\w+)$/
    and $1 > 1024
    and uc $2 eq 'MB'
    and return int($1/1024)." GB";
}

# sometimes we need to rescan disks in LSI (sas + ssd cofigurations mostly)
sub scan4LsiDisks {
  my $port = shift;
  return {} unless $port;
  my %disks;

  my @out = `$LSIUTIL -p$port -a8,0`;
# 0   1  PhysDisk 1     ATA      ST3750528AS      CC44  1221000001000000     1
# 0   3  PhysDisk 2     ATA      INTEL SSDSA2M080 02HD  1221000003000000     3
  foreach (@out){
    next unless /PhysDisk\s+(\d+)\s+(\w+)\s+(\w+(?:\s\w+)?)\s+([\da-zA-Z]+)\s+([\dABCDEF]+)\s+(\d+)\s+$/;
    $disks{$1} = {vendor=>$2, model=>$3, rev=>$4, phy=>$6};
  }

  return \%disks;
}


