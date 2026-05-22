#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 SAP SE or an SAP affiliate company and IronCore contributors
# SPDX-License-Identifier: Apache-2.0

# Mutates <config-dir>/base/libvirt-provider/kustomization.yaml in-place so that
# libvirt-provider is sourced from a local checkout and/or runs a custom image tag.
# Both mutations are opt-in and gated by environment variables; with neither set,
# the script is a no-op.
#
#   LIBVIRT_PROVIDER_CONFIG_DIR  Replace the remote `config/default?ref=...`
#                                kustomize resource with a relative path to a
#                                local libvirt-provider config directory.
#   LIBVIRT_PROVIDER_IMAGE_TAG   Override the libvirt-provider image tag.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <config-dir>" >&2
    exit 1
fi

config_dir=$1
kustomization_dir="$config_dir/base/libvirt-provider"

config_ref="${LIBVIRT_PROVIDER_CONFIG_DIR:-}"
image_tag="${LIBVIRT_PROVIDER_IMAGE_TAG:-}"

if [ -n "$config_ref" ]; then
    cd "$kustomization_dir"
    rel_config=$(relpath "$config_ref" "$kustomization_dir")
    remote_ref=$(grep -oE 'github\.com/ironcore-dev/libvirt-provider/config/default\?ref=[^ ]+' kustomization.yaml)
    kustomize edit remove resource "$remote_ref"
    kustomize edit add resource --no-verify "$rel_config"
fi

if [ -n "$image_tag" ]; then
    cd "$kustomization_dir"
    kustomize edit set image "libvirt-provider=ghcr.io/ironcore-dev/libvirt-provider:$image_tag"
fi
