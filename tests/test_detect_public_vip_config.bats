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

create_cre_mock() {
    local subnet=$1; shift
    local emit_network=${1:-yes}; shift || true

    cat > "$CRE_MOCK" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [ "\$1" = "inspect" ] && [ "\$2" = "ironcore-in-a-box-control-plane" ]; then
EOF
    if [ "$emit_network" = "yes" ]; then
        cat >> "$CRE_MOCK" <<'EOF'
    echo "kind"
EOF
    fi
    cat >> "$CRE_MOCK" <<'EOF'
    exit 0
fi

if [ "$1" = "network" ] && [ "$2" = "inspect" ] && [ "$3" = "kind" ]; then
EOF
    if [ -n "$subnet" ]; then
        cat >> "$CRE_MOCK" <<EOF
    echo "$subnet"
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
