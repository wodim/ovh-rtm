#! /bin/bash
# version: 0.9.4 (2011-12-06)

LC_ALL=POSIX

test -f /etc/redhat-release && distro=`cat /etc/redhat-release`
test -f /etc/gentoo-release &&  distro=`cat /etc/gentoo-release`
test -f /etc/debian_version && distro="Debian "`cat /etc/debian_version`
test -f /etc/SuSE-release && distro=`cat /etc/SuSE-release`
test -f /etc/slackware-version && distro=`cat /etc/slackware-version`
test -f /etc/lsb-release && test -n "`grep -i ubuntu /etc/lsb-release`" && test -f /etc/lsb-release && uv=`grep DISTRIB_DESCRIPTION /etc/lsb-release | cut -d\= -f2` && test -n "$uv" && distro=$uv

test -f /etc/ovhrelease && release_ovh=`cat /etc/ovhrelease`


echo "dINFO_RELEASE_os|$distro"
echo "dINFO_RELEASE_ovh|$release_ovh"
