#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 SAP SE or an SAP affiliate company and IronCore contributors
# SPDX-License-Identifier: Apache-2.0

# Prepares a writable copy of base/ and cluster/ under .tmp/config/ and runs
# all mutate-* scripts against it. Mutate scripts are no-ops unless their
# corresponding override env vars are set (see hack/mutate-*.sh for details).

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
config_dir="$repo_root/.tmp/config"

# Resolve relative env var paths to absolute while still in the caller's CWD,
# so that subsequent `cd`s in mutate scripts don't break path references.
case "${LIBVIRT_PROVIDER_CONFIG_DIR:-}" in
    "" | /*)
        # unset or already absolute — nothing to do
        ;;
    *)
        export LIBVIRT_PROVIDER_CONFIG_DIR="$(cd "$LIBVIRT_PROVIDER_CONFIG_DIR" && pwd)"
        ;;
esac

# Always start fresh
rm -rf "$config_dir"
mkdir -p "$config_dir"
cp -r "$repo_root/base" "$config_dir/base"
cp -r "$repo_root/cluster" "$config_dir/cluster"

# Run all mutate scripts (each is a no-op if its env vars aren't set)
"$repo_root/hack/mutate-libvirt-provider.sh" "$config_dir"
