#!/bin/bash
set -e
if ! ping -c 1 8.8.8.8; then
    echo "Network access test failed."
    exit 1
fi
echo "Network access test passed."
exit 0