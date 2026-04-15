#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 SAP SE or an SAP affiliate company and IronCore contributors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "usage: $0 <container-runtime-binary> <kind-cluster-name> <runtime-overlays-dir>" >&2
    exit 1
fi

runtime_bin=$1; shift
kind_cluster_name=$1; shift
runtime_overlays_dir=$1; shift

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
public_vip_config=$("$repo_root/hack/detect-public-vip-config.sh" "$runtime_bin" "$kind_cluster_name")
public_prefix_ipv4=$(awk -F= '$1 == "PUBLIC_PREFIX_IPV4" {print $2}' <<<"$public_vip_config")
public_cidr_ipv4=$(awk -F= '$1 == "PUBLIC_CIDR_IPV4" {print $2}' <<<"$public_vip_config")

if [ -z "$public_prefix_ipv4" ] || [ -z "$public_cidr_ipv4" ]; then
    echo "failed to detect PUBLIC_PREFIX_IPV4/PUBLIC_CIDR_IPV4" >&2
    exit 1
fi

echo "Detected public VIP configuration:"
echo "$public_vip_config"

ironcore_net_overlay="$runtime_overlays_dir/ironcore-net"
metalbond_client_overlay="$runtime_overlays_dir/metalbond-client"
mkdir -p "$ironcore_net_overlay" "$metalbond_client_overlay"

ironcore_net_base=$(realpath --relative-to "$ironcore_net_overlay" "$repo_root/cluster/local/ironcore-net")
metalbond_client_base=$(realpath --relative-to "$metalbond_client_overlay" "$repo_root/cluster/local/metalbond-client")

cat > "$ironcore_net_overlay/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - $ironcore_net_base

patches:
  - path: public-prefix-patch.yaml
EOF

sed -E "s#--public-prefix=[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]+#--public-prefix=$public_prefix_ipv4#g" \
    "$repo_root/base/ironcore-net/patch-apiserver-deployment.yaml" \
    > "$ironcore_net_overlay/public-prefix-patch.yaml"

if ! grep -Fq -- "--public-prefix=$public_prefix_ipv4" "$ironcore_net_overlay/public-prefix-patch.yaml"; then
    echo "failed to patch public prefix in ironcore-net overlay" >&2
    exit 1
fi

cat > "$metalbond_client_overlay/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - $metalbond_client_base

patches:
  - path: ip-prefix-patch.yaml
EOF

cat > "$metalbond_client_overlay/ip-prefix-patch.yaml" <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: metalbond-client
  namespace: default
spec:
  template:
    spec:
      containers:
        - name: metalbond-arp
          command:
            - spoofer
            - --interface
            - eth0
            - --ip-prefix
            - $public_cidr_ipv4
EOF
