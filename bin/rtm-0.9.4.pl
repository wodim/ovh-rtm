#! /usr/bin/perl
# version: 0.9.4 (2011-12-06)

$ENV{"LC_ALL"} = "POSIX";

use Fcntl;
use strict;
use Socket;
use Time::localtime;
use Symbol qw(gensym);
use IO::Select;
use POSIX qw(dup2);

# Check for root permission
if ($) != 0) {
    die "You are not a root!";
}

# Version of script
my $version = '0.9.4';
my $release_date = '2011-12-06';

# at this hour all information will be send
my $HOUR = 2;

# get uptime
open(FILE, "/proc/uptime") || die("Cannot open /proc/uptime");
my $uptime = <FILE>;
close(FILE);
$uptime =~ /^(\d+)/;
$uptime = $1;

my $script_name = $0;
# get basename of the script
$script_name =~ s/(^.*\/)//;

my $base_dir = '/usr/local/rtm';
my $scripts_dir_daily = '/usr/local/rtm/scripts/daily';
my $scripts_dir_hour = '/usr/local/rtm/scripts/hour';
my $scripts_dir_min = '/usr/local/rtm/scripts/min';
my $rtm_update_ip = '/usr/local/rtm/bin/rtm-update-ip.sh';

chomp(my @scripts_daily = `/bin/ls -1 $scripts_dir_daily`);
chomp(my @scripts_hour = `/bin/ls -1 $scripts_dir_hour`);
chomp(my @scripts_min = `/bin/ls -1 $scripts_dir_min`);

my $env_path = $ENV{'PATH'};
$ENV{'PATH'} = "/usr/local/sbin:/usr/local/bin:$env_path";

# global variable used to report errors from failed scripts
my $script_error = 0;

# determine rtm server ip from mrtg config
my $ipfile = "$base_dir/etc/rtm-ip";
open FP, "$ipfile" or die("failed to open '$ipfile' for reading: $!");
chomp(my $destination_ip = <FP>);
close FP;
if ($destination_ip !~ /^\d+\.\d+\.\d+\.\d+$/) {
    die "failed to read destination ip from '$ipfile': invalid ip: $destination_ip";
}

my $LOCK_FILE = "/var/lock/rtm.flock";
lockProcess();

my $TIMEOUT = 45;
my $MAX_UDP_BUFFER_SIZE = 200;
my $udp_buffer = '';

my $tm = localtime(time);
my $hour = $tm->hour;
my $min = $tm->min;

my @scripts_to_run = ();

# per minute data
push @scripts_to_run, map { "$scripts_dir_min/$_" } @scripts_min;

# hourly data
if ((scalar @ARGV == 0) or (($min >= 0) && ($min <= 5)) or $uptime < 900) {
    send_info("hINFO_uptime|" . $uptime);
    push @scripts_to_run, map { "$scripts_dir_hour/$_" } @scripts_hour;
}

# daily data
if (scalar @ARGV == 0 || (($hour eq $HOUR || $uptime < 900) && $min % 10 == 0)) {
    send_info("dINFO_RTM_version|" . $version);
    push @scripts_to_run, map { "$scripts_dir_daily/$_" } @scripts_daily;
}

# update rtm-ip daily
if (@ARGV > 0 && $hour eq $HOUR && $ARGV[0] == $min) {
    system("$rtm_update_ip &");
}

# run collected scripts in separate processes
my $read_set = IO::Select->new();
my %scripts_output = ();
foreach my $script (@scripts_to_run) {
    my $P_STDOUT_READ = gensym();
    my $P_STDOUT_WRITE = gensym();
    my $P_STDERR_READ = gensym();
    my $P_STDERR_WRITE = gensym();
    pipe $P_STDOUT_READ, $P_STDOUT_WRITE or die "pipe(): $!";
    pipe $P_STDERR_READ, $P_STDERR_WRITE or die "pipe(): $!";
    my @stats = stat($script);
    my $uid =  $stats[4];

    my $pid = fork();
    die "cannot fork: $!" if $pid < 0;
    if ($pid == 0) {
        if($uid > 0) {
            my $gid =  $stats[5];
            drop_priv($uid, $gid)
        }

        dup2(fileno($P_STDOUT_WRITE), 1) or die "dup2(): $!";
        dup2(fileno($P_STDERR_WRITE), 2) or die "dup2(): $!";
        close $P_STDOUT_READ;
        close $P_STDERR_READ;
        close $P_STDOUT_WRITE;
        close $P_STDERR_WRITE;
        my $error = "timeout";
        my $ok = eval {
            local $SIG{ALRM} = sub { die; };
            alarm($TIMEOUT);
            system($script);
            if ($? == -1) {
                $error = "failed to execute '$script': $!";
                die;
            }
        };
        if (!defined($ok)) {
            print STDERR "$error";
            exit 1;
        }
        exit;
    }
    close $P_STDOUT_WRITE;
    close $P_STDERR_WRITE;
    $read_set->add($P_STDOUT_READ);
    $read_set->add($P_STDERR_READ);
    $scripts_output{$pid} = { 'script' => $script,
                              'stdout' => $P_STDOUT_READ,
                              'stderr' => $P_STDERR_READ,
                              'error' => [],
    };
}

# wait for all scripts to complete
while (my @fds = $read_set->can_read()) {
    foreach my $fd (@fds) {
        my $slot;
        foreach my $s (values %scripts_output) {
            if ($s->{'stdout'} == $fd || $s->{'stderr'} == $fd) {
                $slot = $s;
                last;
            }
        }
        unless (defined($slot)) {
            warn "FATAL: got event on unknown file descriptor!";
            $read_set->remove($fd);
            close $fd;
            next;
        }
        my $line = <$fd>;
        if (!$line) {
            $read_set->remove($fd);
            close $fd;
            next;
        }
        chomp($line);
        if ($fd == $slot->{'stderr'}) {
            push @{$slot->{'error'}}, $line;
            print STDERR "$line\n";
        } else {
            send_info($line);
        }
    }
}
while (1) {
    my $pid = waitpid(-1, 0);
    last unless $pid > 0;
    $scripts_output{$pid}->{'status'} = $? >> 8;
}

# find scripts which returned error
foreach my $slot (values %scripts_output) {
    next if $slot->{'status'} == 0;
    $slot->{'script'} =~ m!/([^/]+?)$ !;
    my $script_name = $1;
    my $stderr = join ' ', map { chomp; $_ } @{$slot->{'error'}}; # perl sucks
    if (length $stderr > 20) {
        $stderr = substr($stderr, 0, 150);
        $stderr .= '...';
    }
    chomp($stderr);
    $script_error = "1 $script_name $stderr";
    # TODO: it currently sends errors for the first failed script
    last;
}

send_info("mINFO_RTM_status|$script_error");

unlockProcess();
exit 0;


sub flush_info {
  return if length ($udp_buffer) == 0;
  my $port = 6100 + int(rand(100));

  my $ok = eval {
    local $SIG{ALRM} = sub { print "rtm timeout\n"; die; };
    alarm(10);

    my $proto = getprotobyname('udp');
    socket(Socket_Handle, PF_INET, SOCK_DGRAM, $proto);
    my $iaddr = gethostbyname($destination_ip);
    my $sin = sockaddr_in("$port", $iaddr);
    send(Socket_Handle, $udp_buffer, 10, $sin);
    print $udp_buffer;
    alarm(0);
  };
  if (!defined($ok)) {
    $script_error = "1 send_info() rtm timeout";
    warn "error: $@\n";
  }
  $udp_buffer = '';
}

sub send_info {
  my $message = shift;
  $message = "rtm $message\n";

  if(length($message) > $MAX_UDP_BUFFER_SIZE and length($udp_buffer) == 0){
    $udp_buffer = $message;
    flush_info();
  }elsif(length($message) + length($udp_buffer) >= $MAX_UDP_BUFFER_SIZE){
    flush_info();
  }

  $udp_buffer .= $message;
}

sub drop_priv {
    my ($uid, $gid) = @_;

    # set EGID
    $) = "$gid $gid";
    # set EUID
    $> = $uid + 0;
    if ($> != $uid) {
        die "Can't drop EUID.";
    }
}

sub lockProcess {
    my $pid = $$;

    if (-e "$LOCK_FILE") {
        open(LOCKFILE, $LOCK_FILE) or die "Impossible to open lock file: $LOCK_FILE !!!";
        my $lockPID=<LOCKFILE> || "";
        close(LOCKFILE);

        if ($lockPID !~ m/^\d+$/ ) {
            warn("There is no PID in lock. Something is broken...");
            exit 1;
        } elsif (-e "/proc/$lockPID") {
            exit 0;
        }
        warn("There is a lock file $LOCK_FILE, but no process for it. Overwritting lock file");
    }

    unlink($LOCK_FILE); # in case it's a symlink, sysopen below would refuse to open it, and we would always die()
    # open for writing, create file if it doesn't exist, truncate it if it does, never follow symlinks but fail instead:
    sysopen(LOCKFILE, $LOCK_FILE, O_WRONLY|O_CREAT|O_TRUNC|O_NOFOLLOW, 0600) or die "Impossible to open lock file for writting: $LOCK_FILE !!!";

    print LOCKFILE $pid;
    close(LOCKFILE);
}


sub unlockProcess {
    unlink($LOCK_FILE);
}
