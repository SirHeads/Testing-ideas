#!/bin/bash
#
# File: test_shared_storage_mount.sh
#
# Description: This script verifies that the shared storage volume is correctly
#              mounted inside the container at the expected path (`/mnt/shared`).
#              It checks the output of the `mount` command to confirm the presence
#              of the mount point. This is a critical test for containers that
#              rely on persistent or shared data.
#
# Dependencies: - `mount` and `grep` commands.
#
# Inputs: None.
#
# Outputs:
#   - Exits with status 0 if the shared storage is mounted.
#   - Exits with status 1 if the mount point is not found.
#   - Console output indicates the success or failure of the test.
#

# Exit immediately if a command exits with a non-zero status.
set -e

# Check the output of the `mount` command for a line containing "/mnt/shared".
# The -q flag for grep suppresses output, making it suitable for scripting.
if ! mount | grep -q "/mnt/shared"; then
    echo "Shared storage mount test FAILED. The mount point '/mnt/shared' was not found."
    exit 1
fi

# If the mount point is found, the test passes.
echo "Shared storage mount test PASSED. '/mnt/shared' is correctly mounted."
exit 0