#!/bin/bash
#
# File: check_docker_service.sh
#
# Description: This script checks whether the Docker service (daemon) is active
#              and running within the container. It uses `systemctl` to query the
#              status of the `docker.service`. This is a fundamental check to ensure
#              that the Docker environment is operational before attempting to run
#              any containers.
#
# Dependencies: - A systemd-based container environment.
#               - `systemctl` command must be available.
#
# Inputs: None.
#
# Outputs:
#   - Exits with status 0 if the Docker service is active.
#   - Exits with status 1 if the Docker service is not active.
#   - Console output indicates the success or failure of the test.
#

# Exit immediately if a command exits with a non-zero status.
set -e

# Use `systemctl is-active` to check the Docker service status. The --quiet flag
# ensures that the command only returns an exit code without any console output.
if ! systemctl is-active --quiet docker; then
    echo "Docker service status check FAILED. The Docker daemon is not running."
    exit 1
fi

# If the service is active, the test passes.
echo "Docker service status check PASSED. The service is active."
exit 0