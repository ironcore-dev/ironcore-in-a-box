#!/bin/bash

set -e

echo "Delete storage disks..."
losetup -d /dev/loop0
rm /var/tmp/osd-disk
