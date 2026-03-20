#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 SAP SE or an SAP affiliate company and IronCore contributors
# SPDX-License-Identifier: Apache-2.0

# pods_ready
#
# Sucesfully returns if all k8s pods in all namespaces are in "Running" state.
pods_ready() {
    _assert_k8s_resource_state pods Running 4
    return $?
}

# machines_ready
#
# Succesfully returns if all k8s machines in all namespaces are in "Running"
# state.
machines_ready() {
    _assert_k8s_resource_state machine Running 6
    return $?
}

# get_virtual_ip NAME
#
# Returns IP value of a virtual IP identified by the NAME. The function fails
# if it can't find the virtual IP in the current namespace or if the actual
# value of the IP is '<none>'
get_virtual_ip() {
    if [ "$#" -ne 1 ]; then
        log err "Function '${FUNCNAME[0]}' expects exactly 1 argument. $# given."
        return 1
    fi
    local name=$1; shift
    local ip
    ip=$(kubectl get virtualip "$name" --no-headers -o custom-columns="EXTERNALIP:.status.ip")
    local result=$?
    if [ "$ip" == "<none>" ]; then
        log err "Failed to find VirtualIP $name"
        return 1
    fi
    echo "$ip"
    return $result
}

# _assert_k8s_resource_state RESOURCE_TYPE EXPECTED_STATE STATE_COLUMN
#
# Succesfully returns if all resources of the RESOURCE_TYPE (i.e. "pods"),
# in all namespaces, are in the EXPECTED_STATE (i.e. "Running").
# The argument STATE_COLUMN tells the function which column of the
# 'kubectl get -A' output represents the state of the resource.
_assert_k8s_resource_state() {
    if [ "$#" -ne 3 ]; then
        log err "Function '${FUNCNAME[0]}' expects exactly 3 arguments. $# given."
        return 1
    fi
    local resource=$1; shift
    local state=$1; shift
    local column=$1; shift

    local output
    if ! output=$(kubectl get "$resource" -A --no-headers 2>&1); then
        log err "kubectl failed with: $output"
        return 1
    fi

    if awk -v col="$column" '{print $col;}' <<< "$output" | grep -qvc "$state"; then
        log on_fail "Some '$resource' are not in '$state' state"
        log on_fail "$output"
        return 1
    else
        return 0
    fi
}
