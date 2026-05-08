#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 SAP SE or an SAP affiliate company and IronCore contributors
# SPDX-License-Identifier: Apache-2.0

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

if [ -z "$config_ref" ] && [ -z "$image_tag" ]; then
    exit 0
fi

cd "$kustomization_dir"

if [ -n "$config_ref" ]; then
    rel_config=$(relpath "$config_ref" "$kustomization_dir")
    remote_ref=$(grep -oE 'github\.com/ironcore-dev/libvirt-provider/config/default\?ref=[^ ]+' kustomization.yaml)
    kustomize edit remove resource "$remote_ref"
    kustomize edit add resource --no-verify "$rel_config"
fi

if [ -n "$image_tag" ]; then
    kustomize edit set image "libvirt-provider=ghcr.io/ironcore-dev/libvirt-provider:$image_tag"
fi
