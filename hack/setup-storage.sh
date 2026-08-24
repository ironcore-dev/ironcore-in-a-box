#!/bin/bash

set -e

echo "Prepare storage disks..."
# OSD disk must have a minimum size of 5GB
if [ ! -f /var/tmp/osd-disk0 ]; then
    dd if=/dev/zero of=/var/tmp/osd-disk0 bs=1M count=5120
fi

if ! losetup /dev/loop0 > /dev/null 2>&1; then
    losetup /dev/loop0 /var/tmp/osd-disk0
fi
