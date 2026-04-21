# SPDX-FileCopyrightText: 2026 SAP SE or an SAP affiliate company and IronCore contributors
# SPDX-License-Identifier: Apache-2.0

setup() {
    load "$BATS_SOURCES/bats-support/load.bash"
    load "$BATS_SOURCES/bats-assert/load.bash"
    load "test_helpers/common.sh"

    TMPDIR=$(mktemp -d)
    CRE_MOCK="$TMPDIR/cre-mock.sh"
    RUNTIME_OVERLAYS_DIR="$TMPDIR/runtime-overlays"
}

teardown() {
    rm -rf "$TMPDIR"
}

@test "renders runtime overlays using detected public VIP config" {
    create_cre_mock "172.22.0.0/16"

    run hack/render-public-vip-overlays.sh "$CRE_MOCK" "ironcore-in-a-box" "$RUNTIME_OVERLAYS_DIR"

    assert_success
    assert_line --partial "Detected public VIP configuration:"
    assert_line --partial "PUBLIC_PREFIX_IPV4=172.22.1.1/24"
    assert_line --partial "PUBLIC_CIDR_IPV4=172.22.1.0/24"

    local ironcore_kustomization="$RUNTIME_OVERLAYS_DIR/ironcore-net/kustomization.yaml"
    local metalbond_kustomization="$RUNTIME_OVERLAYS_DIR/metalbond-client/kustomization.yaml"
    local public_prefix_patch="$RUNTIME_OVERLAYS_DIR/ironcore-net/public-prefix-patch.yaml"
    local ip_prefix_patch="$RUNTIME_OVERLAYS_DIR/metalbond-client/ip-prefix-patch.yaml"

    [ -f "$ironcore_kustomization" ]
    [ -f "$metalbond_kustomization" ]
    [ -f "$public_prefix_patch" ]
    [ -f "$ip_prefix_patch" ]

    run grep -E "cluster/local/ironcore-net$" "$ironcore_kustomization"
    assert_success

    run grep -E "cluster/local/metalbond-client$" "$metalbond_kustomization"
    assert_success

    run grep -F -- "--public-prefix=172.22.1.1/24" "$public_prefix_patch"
    assert_success

    run grep -F -- "- 172.22.1.0/24" "$ip_prefix_patch"
    assert_success
}

@test "fails when public VIP config cannot be detected" {
    create_cre_mock ""

    run hack/render-public-vip-overlays.sh "$CRE_MOCK" "ironcore-in-a-box" "$RUNTIME_OVERLAYS_DIR"

    assert_failure
    assert_line --partial "failed to detect IPv4 subnet"
}

@test "fails when ironcore-net patch template has no public-prefix argument" {
    create_cre_mock "172.22.0.0/16"

    local sandbox_repo="$TMPDIR/repo"
    local sandbox_overlays="$TMPDIR/sandbox-overlays"
    mkdir -p \
        "$sandbox_repo/hack" \
        "$sandbox_repo/base/ironcore-net" \
        "$sandbox_repo/cluster/local/ironcore-net" \
        "$sandbox_repo/cluster/local/metalbond-client"

    cp hack/detect-public-vip-config.sh "$sandbox_repo/hack/"
    cp hack/render-public-vip-overlays.sh "$sandbox_repo/hack/"
    chmod +x "$sandbox_repo/hack/detect-public-vip-config.sh" "$sandbox_repo/hack/render-public-vip-overlays.sh"

    cat > "$sandbox_repo/base/ironcore-net/patch-apiserver-deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: apiserver
spec:
  template:
    spec:
      containers:
        - name: kube-apiserver
          command:
            - kube-apiserver
EOF

    run "$sandbox_repo/hack/render-public-vip-overlays.sh" "$CRE_MOCK" "ironcore-in-a-box" "$sandbox_overlays"

    assert_failure
    assert_line --partial "failed to patch public prefix in ironcore-net overlay"
}
