#!/bin/bash
#
#
# File: dummy_fail.sh
#
# Description: This is a simple dummy test script that is designed to always
#              fail. It prints an error message to stderr and exits with a non-zero
#              status code. Its primary purpose is to test the failure-handling
#              logic of the main test runner (`test_runner.sh`) to ensure that it
#              correctly detects and reports failed tests.
#
# Dependencies: None.
#
# Inputs: None.
#
# Outputs:
#   - Exits with status 1.
#   - Prints an error message to stderr.
#

# Print a message to standard error to simulate a real failure message.
echo "This is a dummy test that always fails." >&2
exit 1