#!/bin/bash
set -e
if ! systemctl is-active --quiet docker; then
    echo "Docker service is not running."
    exit 1
fi
echo "Docker service is active."
exit 0