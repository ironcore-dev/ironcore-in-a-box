# SPDX-FileCopyrightText: 2026 SAP SE or an SAP affiliate company and IronCore contributors
# SPDX-License-Identifier: Apache-2.0

# shellcheck disable=SC2030,SC2031

setup() {
    load "$BATS_SOURCES/bats-support/load.bash"
    load "$BATS_SOURCES/bats-assert/load.bash"
    load "test_helpers/common.sh"

    ORIG_DIR=$(pwd)
    SANDBOX=$(mktemp -d)
    FAKE_PROVIDER_DIR="$SANDBOX/fake-provider-config"
    mkdir -p "$FAKE_PROVIDER_DIR"
    mkdir -p "$SANDBOX/base/libvirt-provider" "$SANDBOX/cluster/local/libvirt-provider" "$SANDBOX/hack"

    # Copy real base and cluster content into sandbox
    cp -r "$ORIG_DIR/base/"* "$SANDBOX/base/"
    cp -r "$ORIG_DIR/cluster/"* "$SANDBOX/cluster/"
    cp "$ORIG_DIR/hack/prepare-local-config.sh" "$SANDBOX/hack/"
    cp "$ORIG_DIR/hack/mutate-libvirt-provider.sh" "$SANDBOX/hack/"
    cp "$ORIG_DIR/hack/lib.sh" "$SANDBOX/hack/"
    chmod +x "$SANDBOX/hack/prepare-local-config.sh" "$SANDBOX/hack/mutate-libvirt-provider.sh"

    unset LIBVIRT_PROVIDER_CONFIG_DIR
    unset LIBVIRT_PROVIDER_IMAGE_TAG

    cd "$SANDBOX" || return
}

teardown() {
    cd "$ORIG_DIR" || return
    rm -rf "$SANDBOX"
}

@test "copies base and cluster to .tmp/config without mutations when no env vars set" {
    hack/prepare-local-config.sh

    assert [ -d ".tmp/config/base/libvirt-provider" ]
    assert [ -d ".tmp/config/cluster/local/libvirt-provider" ]

    # kustomization.yaml should be unchanged — still has remote git ref
    run grep -F "github.com/ironcore-dev/libvirt-provider/config/default" .tmp/config/base/libvirt-provider/kustomization.yaml
    assert_success

    run grep "newTag: v0.4.0" .tmp/config/base/libvirt-provider/kustomization.yaml
    assert_success
}

@test "replaces remote resource with local path when LIBVIRT_PROVIDER_CONFIG_DIR is set" {
    export LIBVIRT_PROVIDER_CONFIG_DIR="$FAKE_PROVIDER_DIR"

    hack/prepare-local-config.sh

    # Remote git ref should be gone
    run grep -F "github.com/ironcore-dev/libvirt-provider/config/default" .tmp/config/base/libvirt-provider/kustomization.yaml
    assert_failure

    # Local path should be present (as relative path)
    run grep -F "fake-provider" .tmp/config/base/libvirt-provider/kustomization.yaml
    assert_success

    # Image tag should be unchanged
    run grep "newTag: v0.4.0" .tmp/config/base/libvirt-provider/kustomization.yaml
    assert_success
}

@test "overrides image tag when LIBVIRT_PROVIDER_IMAGE_TAG is set" {
    export LIBVIRT_PROVIDER_IMAGE_TAG="local"

    hack/prepare-local-config.sh

    # Remote git ref should still be present
    run grep -F "github.com/ironcore-dev/libvirt-provider/config/default" .tmp/config/base/libvirt-provider/kustomization.yaml
    assert_success

    # Image tag should be overridden
    run grep "newTag: local" .tmp/config/base/libvirt-provider/kustomization.yaml
    assert_success
}

@test "applies both mutations when both env vars are set" {
    export LIBVIRT_PROVIDER_CONFIG_DIR="$FAKE_PROVIDER_DIR"
    export LIBVIRT_PROVIDER_IMAGE_TAG="local"

    hack/prepare-local-config.sh

    # Remote git ref should be gone
    run grep -F "github.com/ironcore-dev/libvirt-provider/config/default" .tmp/config/base/libvirt-provider/kustomization.yaml
    assert_failure

    # Local path should be present (as relative path)
    run grep -F "fake-provider" .tmp/config/base/libvirt-provider/kustomization.yaml
    assert_success

    # Image tag should be overridden
    run grep "newTag: local" .tmp/config/base/libvirt-provider/kustomization.yaml
    assert_success
}

@test "idempotent: running twice produces same result" {
    export LIBVIRT_PROVIDER_CONFIG_DIR="$FAKE_PROVIDER_DIR"
    export LIBVIRT_PROVIDER_IMAGE_TAG="local"

    hack/prepare-local-config.sh
    local first_run
    first_run=$(cat .tmp/config/base/libvirt-provider/kustomization.yaml)

    hack/prepare-local-config.sh
    local second_run
    second_run=$(cat .tmp/config/base/libvirt-provider/kustomization.yaml)

    [ "$first_run" = "$second_run" ]
}
