#!/bin/bash

set -e

echo "Prepare storage disks..."
# OSD disk must have a minimum size of 5GB
dd if=/dev/zero of=/var/tmp/osd-disk bs=1M count=5120
losetup /dev/loop0 /var/tmp/osd-disk
