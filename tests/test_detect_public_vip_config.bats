# SPDX-FileCopyrightText: 2026 SAP SE or an SAP affiliate company and IronCore contributors
# SPDX-License-Identifier: Apache-2.0

setup() {
    load "$BATS_SOURCES/bats-support/load.bash"
    load "$BATS_SOURCES/bats-assert/load.bash"
    load "test_helpers/common.sh"

    TMPDIR=$(mktemp -d)
    CRE_MOCK="$TMPDIR/cre-mock.sh"
}

teardown() {
    rm -rf "$TMPDIR"
}

@test "detects VIP config for common kind /16 ranges" {
    local cases=(
        "172.18.0.0/16 172.18.1.1/24 172.18.1.0/24 172.18.1.1"
        "172.19.0.0/16 172.19.1.1/24 172.19.1.0/24 172.19.1.1"
        "172.20.0.0/16 172.20.1.1/24 172.20.1.0/24 172.20.1.1"
        "172.21.0.0/16 172.21.1.1/24 172.21.1.0/24 172.21.1.1"
    )
    local c

    for c in "${cases[@]}"; do
        read -r subnet prefix cidr vip <<<"$c"
        create_cre_mock "$subnet"

        run hack/detect-public-vip-config.sh "$CRE_MOCK" "ironcore-in-a-box"

        assert_success
        assert_line "PUBLIC_PREFIX_IPV4=$prefix"
        assert_line "PUBLIC_CIDR_IPV4=$cidr"
        assert_line "PUBLIC_VIP_IPV4=$vip"
    done
}

@test "detects VIP config for /24 ranges" {
    create_cre_mock "10.88.7.0/24"

    run hack/detect-public-vip-config.sh "$CRE_MOCK" "ironcore-in-a-box"

    assert_success
    assert_line "PUBLIC_PREFIX_IPV4=10.88.7.1/24"
    assert_line "PUBLIC_CIDR_IPV4=10.88.7.0/24"
    assert_line "PUBLIC_VIP_IPV4=10.88.7.1"
}

@test "fails when kind network has no IPv4 subnet" {
    create_cre_mock ""

    run hack/detect-public-vip-config.sh "$CRE_MOCK" "ironcore-in-a-box"

    assert_failure
    assert_line --partial "failed to detect IPv4 subnet"
}
