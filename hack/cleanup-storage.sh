#!/bin/bash

set -e

echo "Delete storage disks..."
if losetup /dev/loop0 > /dev/null 2>&1; then
    losetup -d /dev/loop0
fi

if [ -f /var/tmp/osd-disk0 ]; then
    rm /var/tmp/osd-disk0
fi
