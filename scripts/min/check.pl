#! /usr/bin/perl
# version: 0.9.4 (2011-12-06)

$ENV{"LC_ALL"} = "POSIX";

use strict;

if (`dmesg | grep -i "allocation failed"`) {
        print "mCHECK_vm|1\n";
} else {
        print "mCHECK_vm|\n";
}

if (`dmesg | grep -i "Oops"`) {
        print "mCHECK_oops|1\n";
} else {
        print "mCHECK_oops|\n";
}
