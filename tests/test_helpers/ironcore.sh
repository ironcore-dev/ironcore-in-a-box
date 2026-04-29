#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 SAP SE or an SAP affiliate company and IronCore contributors
# SPDX-License-Identifier: Apache-2.0

# check_example_machine_ssh VIP
#
# Attempt to ssh into the example machine with the default credentials via the
# virtual IP address VIP. If the ssh attempt was successful, this function
# returns successfully as well.
check_example_machine_ssh() {
    if [ "$#" -ne 1 ]; then
        log err "Function '${FUNCNAME[0]}' expects exactly 1 argument. $# given."
        return 1
    fi
    local ip=$1; shift
    sshpass -p "best123" ssh "$ip" -lironcore -oConnectTimeout=10 -oStrictHostKeyChecking=no hostname
    return $?
}

# dump_failed_pod_logs
#
# Find all pods not in "Running" state and dump their logs. This helps diagnose
# why pods failed to start during cluster setup.
dump_failed_pod_logs() {
    local pods
    pods=$($KUBECTL_CTX get pods -A --no-headers | awk '$4 != "Running" {print $1, $2}')
    if [ -z "$pods" ]; then
        log info "No non-running pods found."
        return 0
    fi
    while read -r ns pod; do
        log err "--- Logs for $ns/$pod ---"
        log err "$($KUBECTL_CTX logs -n "$ns" "$pod" --all-containers=true --tail=50 2>&1)" || true
    done <<< "$pods"
}

# deploy_ironcore
#
# Deploy the ironcore-in-a-box kind cluster by running "make up". If a cluster
# with the same name already exists, it will be reused.
# This function will wait for all pods to be in the "Running" state before
# successfully returning. Maximum timeout of this function is approximately
# 11 minutes.
deploy_ironcore() {
    local output
    output=$($KIND get clusters)
    if [ "$output" == "$KIND_CLUSTER_NAME" ]; then
        log warn "Re-using existing $KIND_CLUSTER_NAME cluster"
    else
        log info "Building local kind node image..."
        docker build -t ironcore-dev/kind-node:local .
        log info "Running 'make up' to spin up ironcore-in-a-box cluster. This may take a while..."
        make up KIND_IMAGE=ironcore-dev/kind-node:local
    fi
    if ! wait_for 600 pods_ready; then
        log err "Pods did not become ready in time. Dumping logs of non-running pods:"
        dump_failed_pod_logs
        return 1
    fi
    succeed_for 10 60 pods_ready
}
