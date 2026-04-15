# SPDX-FileCopyrightText: 2026 SAP SE or an SAP affiliate company and IronCore contributors
# SPDX-License-Identifier: Apache-2.0

setup() {
    load "$BATS_SOURCES/bats-support/load.bash"
    load "$BATS_SOURCES/bats-assert/load.bash"

    TMPDIR=$(mktemp -d)
    CRE_MOCK="$TMPDIR/cre-mock.sh"
}

teardown() {
    rm -rf "$TMPDIR"
}

# create_cre_mock SUBNET [EMIT_NETWORK] [INSPECT_NETWORKS] [BRIDGE_SUBNET]
#
# Generate a mock container-runtime executable at $CRE_MOCK that implements the
# two commands used by hack/detect-public-vip-config.sh:
#   * inspect <cluster>-control-plane
#   * network inspect kind
#
# Example:
#   create_cre_mock "172.19.0.0/16"
#   run hack/detect-public-vip-config.sh "$CRE_MOCK" "ironcore-in-a-box"
#   assert_line "PUBLIC_CIDR_IPV4=172.19.1.0/24"
#
# If EMIT_NETWORK is "no", the mock simulates missing network discovery.
# INSPECT_NETWORKS may contain multiple network names separated by newlines.
create_cre_mock() {
    local subnet=$1; shift
    local emit_network=${1:-yes}; shift || true
    local inspect_networks=${1:-kind}; shift || true
    local bridge_subnet=${1:-}; shift || true

    cat > "$CRE_MOCK" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [ "\$1" = "inspect" ] && [ "\$2" = "ironcore-in-a-box-control-plane" ]; then
EOF
    if [ "$emit_network" = "yes" ]; then
        cat >> "$CRE_MOCK" <<EOF
    cat <<'NETWORKS'
$inspect_networks
NETWORKS
EOF
    fi
    cat >> "$CRE_MOCK" <<'EOF'
    exit 0
fi

if [ "$1" = "network" ] && [ "$2" = "inspect" ]; then
    if [ "$3" = "kind" ]; then
EOF
    if [ -n "$subnet" ]; then
        cat >> "$CRE_MOCK" <<EOF
        echo "$subnet"
EOF
    fi
    cat >> "$CRE_MOCK" <<'EOF'
        exit 0
    fi
EOF
    if [ -n "$bridge_subnet" ]; then
        cat >> "$CRE_MOCK" <<EOF
    if [ "\$3" = "bridge" ]; then
        echo "$bridge_subnet"
        exit 0
    fi
EOF
    fi
    cat >> "$CRE_MOCK" <<'EOF'
    exit 0
fi

echo "unexpected args: $*" >&2
exit 1
EOF

    chmod +x "$CRE_MOCK"
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

@test "fails when network cannot be detected" {
    create_cre_mock "" "no"

    run hack/detect-public-vip-config.sh "$CRE_MOCK" "ironcore-in-a-box"

    assert_failure
    assert_line --partial "failed to detect container network"
}

@test "prefers kind network when multiple networks are attached" {
    create_cre_mock "172.30.0.0/16" "yes" $'bridge\nkind' "10.88.7.0/24"

    run hack/detect-public-vip-config.sh "$CRE_MOCK" "ironcore-in-a-box"

    assert_success
    assert_line "PUBLIC_PREFIX_IPV4=172.30.1.1/24"
    assert_line "PUBLIC_CIDR_IPV4=172.30.1.0/24"
    assert_line "PUBLIC_VIP_IPV4=172.30.1.1"
}
