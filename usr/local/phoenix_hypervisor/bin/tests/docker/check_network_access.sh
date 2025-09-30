#!/bin/bash
#
# File: check_network_access.sh
#
# Description: This script tests for basic internet connectivity from within the
#              container. It sends a single ICMP packet (ping) to a reliable
#              public IP address (Google's public DNS server, 8.8.8.8). A successful
#              ping indicates that the container's networking is correctly configured
#              for outbound traffic.
#
# Dependencies: - `ping` command must be available.
#
# Inputs: None.
#
# Outputs:
#   - Exits with status 0 if the ping is successful.
#   - Exits with status 1 if the ping fails.
#   - Console output indicates the success or failure of the test.
#

# Exit immediately if a command exits with a non-zero status.
set -e

# Ping Google's public DNS server once (-c 1). If the command fails, it means
# there is no network route to the public internet.
if ! ping -c 1 8.8.8.8; then
    echo "Network access test FAILED. The container cannot reach the public internet."
    exit 1
fi

# If the ping is successful, the test passes.
echo "Network access test PASSED."
exit 0