#!/bin/bash
#
# File: test_docker_hello_world.sh
#
# Description: This is a fundamental integration test for the Docker setup. It
#              attempts to run the standard `hello-world` Docker image. A successful
#              run of this container verifies that the Docker daemon is running, can
#              pull images from Docker Hub, and can execute a container, confirming
#              that the end-to-end Docker functionality is working.
#
# Dependencies: - Docker daemon must be running and configured.
#               - Network access to pull the `hello-world` image.
#
# Inputs: None.
#
# Outputs:
#   - Exits with status 0 if the `hello-world` container runs successfully.
#   - Exits with status 1 if the command fails.
#   - Console output indicates the success or failure of the test.
#

# Exit immediately if a command exits with a non-zero status.
set -e

# Attempt to run the hello-world container. Docker will automatically pull the
# image if it's not present locally.
if ! docker run hello-world; then
    echo "Docker hello-world integration test FAILED."
    exit 1
fi

# If the container runs without error, the test is successful.
echo "Docker hello-world integration test PASSED."
exit 0