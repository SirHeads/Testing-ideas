#!/bin/bash
#
# File: check_dns_resolution.sh
#
# Description: This test script verifies that DNS resolution is functioning correctly
#              from within the container. It uses the `nslookup` command to resolve
#              a common domain name (google.com). A successful resolution is
#              critical for containers that need to access the internet.
#
# Dependencies: - `nslookup` (provided by dnsutils or bind-utils package).
#
# Inputs: None.
#
# Outputs:
#   - Exits with status 0 if DNS resolution is successful.
#   - Exits with status 1 if DNS resolution fails.
#   - Console output indicates the success or failure of the test.
#

# Exit immediately if a command exits with a non-zero status.
set -e

# Attempt to resolve google.com. If the command fails, it means DNS is not working.
if ! nslookup google.com; then
    echo "DNS resolution test FAILED. The container cannot resolve external domain names."
    exit 1
fi

# If nslookup succeeds, the test passes.
echo "DNS resolution test PASSED."
exit 0