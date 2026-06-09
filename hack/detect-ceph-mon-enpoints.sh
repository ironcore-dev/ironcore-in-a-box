#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 SAP SE or an SAP affiliate company and IronCore contributors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="$SCRIPT_DIR/../.tmp/config/cluster/local/ceph-volume-provider/patch-manager-deployment.yaml"

RETRY_INTERVAL=${RETRY_INTERVAL:-5}
MAX_RETRIES=${MAX_RETRIES:-20}

# Retry until the rook-ceph-mon-endpoints configmap exists and contains at least
# one endpoint. The configmap will only be created and populated during the rook
# cluster creation.
monitors=""
for ((i = 1; i <= MAX_RETRIES; i++)); do
  raw=$(kubectl -n rook-ceph get configmap rook-ceph-mon-endpoints -o jsonpath='{.data.data}' 2>/dev/null || true)

  if [[ -n "$raw" ]]; then
    parsed=$(echo "$raw" | tr ',' '\n' | sed 's/^[^=]*=//' | tr '\n' ',' | sed 's/,$//')
    if [[ -n "$parsed" ]]; then
      monitors="$parsed"
      break
    fi
  fi

  echo "Waiting for ceph mon endpoints (attempt $i/$MAX_RETRIES)..."
  sleep "$RETRY_INTERVAL"
done

if [[ -z "$monitors" ]]; then
  echo "Error: timed out waiting for ceph mon endpoints" >&2
  exit 1
fi

echo "Detected ceph monitors: $monitors"

# Replace the --ceph-monitors= value in the patch file
sed "s|--ceph-monitors=.*|--ceph-monitors=$monitors|" "$PATCH_FILE" > "$PATCH_FILE.tmp" && mv "$PATCH_FILE.tmp" "$PATCH_FILE"

echo "Updated $PATCH_FILE"
