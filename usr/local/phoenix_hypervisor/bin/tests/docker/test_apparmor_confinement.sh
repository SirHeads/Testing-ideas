#!/bin/bash
#
# File: test_apparmor_confinement.sh
#
# Description: This test script checks for AppArmor denial messages related to a
#              specific container (hardcoded as lxc-902) in the host's kernel
#              message buffer (`dmesg`). The presence of such messages would
#              indicate that the AppArmor profile is too restrictive and is
#              blocking legitimate operations, which is a critical issue for
#              nested container environments like Docker-in-LXC.
#
# Dependencies: - `dmesg` and `grep` commands.
#               - Access to the host's kernel message buffer.
#
# Inputs: None.
#
# Outputs:
#   - Exits with status 0 if no relevant AppArmor denials are found.
#   - Exits with status 1 if AppArmor denials for the specified container are detected.
#   - Console output indicates the success or failure of the test.
#

# Exit immediately if a command exits with a non-zero status.
set -e

# Search the kernel message buffer for lines indicating an AppArmor denial
# that is also associated with the specific container profile "lxc-902".
# The `if` condition will be true if `grep` finds any matching lines.
if dmesg | grep "apparmor=\"DENIED\"" | grep "lxc-902"; then
    echo "AppArmor confinement test FAILED. Denial messages were found for container 902."
    exit 1
fi

# If no matching denial messages are found, the test passes.
echo "AppArmor confinement test PASSED. No denials detected for container 902."
exit 0