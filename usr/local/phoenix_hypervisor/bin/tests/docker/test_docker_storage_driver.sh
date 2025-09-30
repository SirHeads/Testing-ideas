#!/bin/bash
#
# File: test_docker_storage_driver.sh
#
# Description: This test script verifies that the Docker daemon is configured to
#              use the `fuse-overlayfs` storage driver. This specific driver is
#              required for running Docker inside an unprivileged LXC container
#              without needing to modify the underlying AppArmor profile, making
#              this a critical configuration check for system stability.
#
# Dependencies: - Docker daemon must be running.
#
# Inputs: None.
#
# Outputs:
#   - Exits with status 0 if the storage driver is `fuse-overlayfs`.
#   - Exits with status 1 if a different storage driver is in use.
#   - Console output indicates the success or failure of the test.
#

# Exit immediately if a command exits with a non-zero status.
set -e

# Use `docker info` with a Go template to extract the name of the storage driver.
storage_driver=$(docker info --format '{{.Driver}}')

# Check if the extracted driver name matches the required "fuse-overlayfs".
if [ "$storage_driver" != "fuse-overlayfs" ]; then
    echo "Docker storage driver test FAILED. Expected 'fuse-overlayfs' but found '$storage_driver'."
    exit 1
fi

# If the driver is correct, the test passes.
echo "Docker storage driver test PASSED. Correctly configured as 'fuse-overlayfs'."
exit 0