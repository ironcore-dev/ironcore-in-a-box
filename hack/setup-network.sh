#!/bin/bash

set -e
# Print message to console
echo "Customize network in progress..."

# Some environments disable ipv6 per default
sysctl -w net.ipv6.conf.all.disable_ipv6=0

# Create and configure overlay-tun interface
ip link add overlay-tun type ip6tnl mode any external ttl 32
ip link set mtu 1500 dev overlay-tun
ip addr add 2001:db8:dead:beef::1/128 dev overlay-tun
ip link set overlay-tun up

# Configure system settings
sysctl -w net.ipv6.conf.all.forwarding=1
sysctl -w net.ipv4.conf.eth0.rp_filter=0
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.overlay-tun.rp_filter=0

# Add iptables rule
iptables -t mangle -I PREROUTING 1 -i overlay-tun -j MARK --set-mark 1

# Configure routing
echo '100 ironcore_eth0' >> /etc/iproute2/rt_tables
ip route add default via 172.18.0.1 dev eth0 table 100
ip rule add fwmark 1 lookup 100

# Add IPv6 route with retry mechanism
for i in {1..3}; do
    ip -6 route add 2001:db8:fefe::/48 via fe80::1 dev dtap0 && break || \
    { echo "Retrying route addition in 1s..."; sleep 1; }
done

# Add permanent neighbor entry
ip -6 neigh add fe80::1 lladdr 22:22:22:22:22:00 dev dtap0 router nud permanent
ip -6 neigh add fe80::1 lladdr 22:22:22:22:22:01 dev dtap1 router nud permanent