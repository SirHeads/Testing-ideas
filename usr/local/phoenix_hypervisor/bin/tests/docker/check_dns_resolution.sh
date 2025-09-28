#!/bin/bash
set -e
if ! nslookup google.com; then
    echo "DNS resolution test failed."
    exit 1
fi
echo "DNS resolution test passed."
exit 0