#!/bin/bash
set -e
if ! docker run hello-world; then
    echo "Docker hello-world test failed."
    exit 1
fi
echo "Docker hello-world test passed."
exit 0