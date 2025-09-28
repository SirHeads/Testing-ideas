#!/bin/bash
set -e
storage_driver=$(docker info --format '{{.Driver}}')
if [ "$storage_driver" != "fuse-overlayfs" ]; then
    echo "Docker storage driver is not fuse-overlayfs."
    exit 1
fi
echo "Docker storage driver is fuse-overlayfs."
exit 0