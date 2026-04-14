#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 SAP SE or an SAP affiliate company and IronCore contributors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

fail() {
    echo "$1" >&2
    exit 1
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "usage: $0 <container-runtime-binary> [kind-cluster-name]" >&2
    exit 1
fi

runtime_bin=$1; shift
kind_cluster_name=${1:-ironcore-in-a-box}
kind_control_plane="${kind_cluster_name}-control-plane"

network_name=$("$runtime_bin" inspect "$kind_control_plane" \
    --format '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}}{{"\n"}}{{end}}' 2>/dev/null | head -n1 || true)

if [ -z "$network_name" ]; then
    fail "failed to detect container network for $kind_control_plane"
fi

subnet_ipv4=""
subnet_ipv4=$("$runtime_bin" network inspect "$network_name" \
    --format '{{range .IPAM.Config}}{{println .Subnet}}{{end}}' 2>/dev/null \
    | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+$/ { print; exit }' || true)

if [ -z "$subnet_ipv4" ]; then
    fail "failed to detect IPv4 subnet for network '$network_name'"
fi

network=${subnet_ipv4%/*}
prefix_len=${subnet_ipv4#*/}
IFS='.' read -r o1 o2 o3 _ <<<"$network"

if [ -z "${o1:-}" ] || [ -z "${o2:-}" ] || [ -z "${o3:-}" ] || ! [[ "$prefix_len" =~ ^[0-9]+$ ]]; then
    fail "invalid subnet format: $subnet_ipv4"
fi

if [ "$prefix_len" -le 16 ]; then
    vip_base="$o1.$o2.1"
elif [ "$prefix_len" -le 24 ]; then
    vip_base="$o1.$o2.$o3"
else
    fail "unsupported subnet prefix length '$prefix_len' for '$subnet_ipv4'"
fi

cat <<EOF
PUBLIC_PREFIX_IPV4=${vip_base}.1/24
PUBLIC_CIDR_IPV4=${vip_base}.0/24
PUBLIC_VIP_IPV4=${vip_base}.1
EOF
