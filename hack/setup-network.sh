#!/bin/bash
# SPDX-FileCopyrightText: SAP SE or an SAP affiliate company and IronCore contributors
# SPDX-License-Identifier: Apache-2.0


set -e
# Print message to console
echo "Customize network in progress..."

# Some environments disable ipv6 per default
sysctl -w net.ipv6.conf.all.disable_ipv6=0

# Create and configure overlay-tun interface
if ! ip link show overlay-tun &>/dev/null; then
    ip link add overlay-tun type ip6tnl mode any external ttl 32
    ip link set mtu 1500 dev overlay-tun
    ip addr add 2001:db8:dead:beef::1/128 dev overlay-tun
    ip link set overlay-tun up
fi

# Configure system settings
sysctl -w net.ipv6.conf.all.forwarding=1
sysctl -w net.ipv4.conf.eth0.rp_filter=0
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.overlay-tun.rp_filter=0

# Add iptables rule
if ! iptables -t mangle -L PREROUTING | grep -q "overlay-tun.*MARK.*1"; then
    iptables -t mangle -I PREROUTING 1 -i overlay-tun -j MARK --set-mark 1
fi

# Configure routing
# Use the iproute2 drop-in directory instead of appending to the legacy
# monolithic /etc/iproute2/rt_tables, which is no longer shipped on newer
# ubuntu/iproute2 versions used by recent kindest/node base images.
# mkdir -p ensures the directory exists on minimal container rootfs.
mkdir -p /etc/iproute2/rt_tables.d
if [ ! -f /etc/iproute2/rt_tables.d/ironcore.conf ] || ! grep -q "ironcore_eth0" /etc/iproute2/rt_tables.d/ironcore.conf; then
    echo '100 ironcore_eth0' > /etc/iproute2/rt_tables.d/ironcore.conf
fi

# Add route to custom table if it doesn't exist
if ! ip route show table 100 | grep -q "default via"; then
    DEFAULT_GW=$(ip r | grep default | awk '{print $3}')
    if [ -n "$DEFAULT_GW" ]; then
        ip route add default via "$DEFAULT_GW" dev eth0 table 100
    fi
fi

# Add ip rule if it doesn't exist
if ! ip rule show | grep -q "fwmark 1 lookup 100"; then
    ip rule add fwmark 1 lookup 100
fi

# Add IPv6 route with retry mechanism
for i in {1..10}; do
    ip -6 route add 2001:db8:fefe::/48 via fe80::1 dev dtap0 2>/dev/null && break || \
    { echo "Retrying route addition in 1s..."; sleep 1; }
done

# Add permanent neighbor entry
ip -6 neigh add fe80::1 lladdr 22:22:22:22:22:00 dev dtap0 router nud permanent 2>/dev/null || true
ip -6 neigh add fe80::1 lladdr 22:22:22:22:22:01 dev dtap1 router nud permanent 2>/dev/null || true
