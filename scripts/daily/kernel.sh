#! /bin/bash
# version: 0.9.4 (2011-12-06)

LC_ALL=POSIX

rel=`uname -r`
ver=`uname -v`

if [ ! -z "$ver" ]; then
    echo "dINFO_KERNEL_release|$rel";
    echo "dINFO_KERNEL_version|$ver"
fi
