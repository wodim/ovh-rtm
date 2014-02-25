#! /bin/bash
# version: 0.9.4 (2011-12-06)

LC_ALL=POSIX

DIR='/usr/local/rtm'

# main interface from route:
mainif=`route -n | grep "^0.0.0.0" | awk '{print $8}' | tail -1`

if test -n "$mainif"; then
	ips=`ifconfig $mainif | awk 'NR == 2 { print $2 }' | cut -f2 -d':' | egrep '[0-9]+(\.[0-9]+){3}'`
else
	for iface in 'eth0' 'eth1'; do
		ips=`ifconfig $iface 2>/dev/null | awk 'NR == 2 { print $2 }' | cut -f2 -d':' | egrep '[0-9]+(\.[0-9]+){3}'`
		if test -n "$ips"; then break; fi;
	done;
fi;

arpa=`echo "$ips" | sed "s/\./ /g" | awk '{print $3"."$2"."$1}'`;
ip=`host -t A mrtg.$arpa.in-addr.arpa $DNSSERVER 2>/dev/null | tail -n 1 | sed -ne 's/.*[\t ]\([0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p'`
if [ -z "$ip" ]; then
  echo "No IP from OVH network or couldn't define MRTG server! Please contact OVH support."
  exit 1;
fi
echo $ip > "$DIR/etc/rtm-ip"

