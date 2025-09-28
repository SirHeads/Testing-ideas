#!/bin/bash
set -e
if ! mount | grep -q "/mnt/shared"; then
    echo "Shared storage is not mounted."
    exit 1
fi
echo "Shared storage is mounted."
exit 0