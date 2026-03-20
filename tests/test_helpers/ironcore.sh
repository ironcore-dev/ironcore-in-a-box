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

# deploy_ironcore
#
# Deploy the ironcore-in-a-box kind cluster by running "make up". If a cluster
# with the same name already exists, it will be reused.
# This function will wait for all pods to be in the "Running" state before
# successfully returning. Maximum timeout of this function is approximately
# 11 minutes.
deploy_ironcore() {
    local output
    output=$(kind get clusters)
    if [ "$output" == "ironcore-in-a-box" ]; then
        log warn "Re-using existing ironcore-in-a-box cluster"
    else
        log info "Running 'make up' to spin up ironcore-in-a-box cluster. This may take a while..."
        make up
    fi
    wait_for 600 pods_ready
    succeed_for 10 60 pods_ready
}
