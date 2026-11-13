#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 SAP SE or an SAP affiliate company and IronCore contributors
# SPDX-License-Identifier: Apache-2.0

# Mutates <config-dir> to switch all controller-runtime IronCore components
# to JSON log output (zap json encoder) when IRONCORE_LOG_FORMAT=json.
#
# Default (env unset or any other value): no-op. Components emit
# human-readable console-mode zap output as shipped by controller-runtime
# --zap-devel=true.
#
# With IRONCORE_LOG_FORMAT=json: appends --zap-encoder=json to the
# container args of the following components' manager containers:
#
#   * metalnet (DaemonSet, metalnet-system)
#   * libvirt-provider (DaemonSet, libvirt-provider-system)
#   * ironcore-controller-manager (Deployment, ironcore-system)
#   * ironcore-net-controller-manager (Deployment, ironcore-net-system)
#   * apinetlet-controller-manager (Deployment, apinetlet-system)
#   * metalnetlet-controller-manager (Deployment, metalnetlet-system)
#
# Not touched by this script (see docs/observability.md TBD for details):
#   * ironcore-apiserver, ironcore-net-apiserver — klog-based, upstream
#     does not surface --logging-format
#   * metalbond, metalbond-client — logrus, no CLI JSON switch
#   * dpservice — DPDK EAL logger, no JSON option
#
# The env var is set automatically by `make observability`. To flip the
# default without invoking observability, export it before `make up`:
#
#   export IRONCORE_LOG_FORMAT=json
#   make up

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <config-dir>" >&2
    exit 1
fi

config_dir=$1
log_format="${IRONCORE_LOG_FORMAT:-}"

if [ "$log_format" != "json" ]; then
    # unset or set to anything other than "json" — nothing to do
    exit 0
fi

# Each entry: <kustomization-dir>:<target-kind>:<target-name>:<target-namespace>
# All 6 targets currently have their manager container at containers[0], as of
# the pinned upstream versions in this iiab base. If a future upstream version
# reorders containers, this script will need to be updated (it targets index 0
# via JSON-6902 rather than by container name, because kustomize
# strategic-merge on `args` REPLACES the list rather than appending — there is
# no clean append-in-place idiom for a scalar container-arg list without
# specifying an index).
entries=(
    "$config_dir/base/metalnet:DaemonSet:metalnet-controller-manager:metalnet-system"
    "$config_dir/cluster/local/libvirt-provider:DaemonSet:libvirt-provider-controller-manager:libvirt-provider-system"
    "$config_dir/base/ironcore:Deployment:ironcore-controller-manager:ironcore-system"
    "$config_dir/base/ironcore-net:Deployment:ironcore-net-controller-manager:ironcore-net-system"
    "$config_dir/base/apinetlet:Deployment:apinetlet-controller-manager:apinetlet-system"
    "$config_dir/base/metalnetlet:Deployment:metalnetlet-controller-manager:metalnetlet-system"
)

for entry in "${entries[@]}"; do
    IFS=: read -r kdir kind name namespace <<<"$entry"
    patch_file="$kdir/zap-json-encoder.yaml"
    # JSON-6902 op-add on the args list. `/-` is the JSON Pointer "end of
    # array" marker, so this appends without needing to know the current
    # args list length.
    cat > "$patch_file" <<EOF
- op: add
  path: /spec/template/spec/containers/0/args/-
  value: --zap-encoder=json
EOF
    (
        cd "$kdir"
        kustomize edit add patch \
            --path zap-json-encoder.yaml \
            --group apps \
            --version v1 \
            --kind "$kind" \
            --name "$name" \
            --namespace "$namespace"
    )
done
