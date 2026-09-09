#!/bin/bash
# SPDX-FileCopyrightText: SAP SE or an SAP affiliate company and IronCore contributors
# SPDX-License-Identifier: Apache-2.0


set -e

echo "Delete storage disks..."
if losetup /dev/loop0 > /dev/null 2>&1; then
    losetup -d /dev/loop0
fi

if [ -f /var/tmp/osd-disk0 ]; then
    rm /var/tmp/osd-disk0
fi
