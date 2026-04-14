# SPDX-FileCopyrightText: 2026 SAP SE or an SAP affiliate company and IronCore contributors
# SPDX-License-Identifier: Apache-2.0

setup_file() {
    load "test_helpers/common.sh"
    load "test_helpers/ironcore.sh"
    load "test_helpers/k8s.sh"
    deploy_ironcore
}

setup() {
    load "$BATS_SOURCES/bats-support/load.bash"
    load "$BATS_SOURCES/bats-assert/load.bash"
    load "test_helpers/common.sh"
    load "test_helpers/ironcore.sh"
    load "test_helpers/k8s.sh"
}

teardown() {
    # Test-specific teardowns
    if [ "$BATS_TEST_DESCRIPTION" == "Deploy VM" ]; then
        log info "Tearing down $BATS_TEST_DESCRIPTION"
        $KUBECTL_CTX delete -f "$EXAMPLES/network/examples/network.yaml"
        apply_networkinterface_example delete
        $KUBECTL_CTX delete -f "$EXAMPLES/machine/machine.yaml"
    fi

}

apply_networkinterface_example() {
    local action=$1; shift
    if [ "$action" != "apply" ] && [ "$action" != "delete" ]; then
        log err "Invalid action for apply_networkinterface_example: '$action'. Expected apply|delete."
        return 1
    fi
    local runtime="docker"
    command -v docker &>/dev/null || runtime="podman"
    local vip
    vip=$(hack/detect-public-vip-config.sh "$runtime" "$KIND_CLUSTER_NAME" | awk -F= '$1 == "PUBLIC_VIP_IPV4" {print $2}')
    sed -E "s#^([[:space:]]*virtualIP:).*#\\1 $vip#g" "$EXAMPLES/network/examples/networkinterface.yaml" | $KUBECTL_CTX "$action" -f -
}

@test "Deploy VM" {
    $KUBECTL_CTX apply -f "$EXAMPLES/network/examples/network.yaml"
    apply_networkinterface_example apply
    $KUBECTL_CTX apply -f "$EXAMPLES/machine/machine.yaml"

    wait_for 600 machines_ready

    local machine_ip
    machine_ip=$(get_virtual_ip webapp)
    wait_for 60 check_example_machine_ssh "$machine_ip"
}
