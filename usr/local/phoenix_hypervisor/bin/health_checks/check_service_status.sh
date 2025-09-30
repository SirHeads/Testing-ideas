#!/bin/bash
#
# File: check_service_status.sh
#
# Description: This script serves as a centralized health checker for various
#              critical services within the Phoenix Hypervisor ecosystem, such as
#              Nginx, vLLM, and Qdrant. It provides a unified interface to
#              perform service-specific health validations.
#
# Dependencies: - `phoenix_hypervisor_common_utils.sh` for logging and utilities.
#               - `curl` and `lsof` for performing the checks.
#
# Inputs:
#   --service <service_name>: The name of the service to check (e.g., nginx, vllm, qdrant).
#   --port <port_number>: (Required for vLLM) The port number the vLLM service is running on.
#
# Outputs:
#   - Exits with status 0 if the specified service is healthy.
#   - Exits with a non-zero status and logs an error if the service is unhealthy
#     or if the script is called with invalid arguments.
#   - Console output provides detailed logs of the health check process.
#

# --- Source common utilities ---
# The common_utils.sh script provides shared functions for logging, error handling, etc.
source "/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh"

# --- Function Definitions ---

#
# Function: check_nginx
# Description: Checks if the Nginx service is responsive by sending a request to the root URL.
#
check_nginx() {
    if curl --fail --silent http://localhost > /dev/null; then
        log_info "Nginx health check PASSED. The service is responsive."
        return 0
    else
        log_error "Nginx health check FAILED. The service is not responding."
        return 1
    fi
}

#
# Function: check_vllm
# Description: Checks the health of a vLLM service instance. It verifies that a
#              process is listening on the specified port and that the /health
#              endpoint is responsive.
# Arguments:
#   $1 - The port number of the vLLM service.
#
check_vllm() {
    local port="$1"
    # First, verify that a process is listening on the specified port.
    if ! lsof -i:"$port" -sTCP:LISTEN -t >/dev/null; then
        log_error "vLLM health check FAILED. No process is listening on port $port."
        exit 1
    fi
    # Second, check the vLLM API's health endpoint.
    if curl --fail --silent http://localhost:"$port"/health > /dev/null; then
        log_info "vLLM on port $port health check PASSED. The service is healthy."
        return 0
    else
        log_error "vLLM on port $port health check FAILED. The API is not responding."
        return 1
    fi
}

#
# Function: check_qdrant
# Description: Checks if the Qdrant service is healthy by querying its healthz
#              endpoint through the Nginx reverse proxy.
#
check_qdrant() {
    if curl --fail --silent http://localhost/qdrant/healthz > /dev/null; then
        log_info "Qdrant health check PASSED. The service is healthy."
        return 0
    else
        log_error "Qdrant health check FAILED. The service is not responding via Nginx."
        return 1
    fi
}

# --- Main Script Logic ---

# Initialize variables for command-line arguments.
SERVICE=""
PORT=""

# Parse command-line arguments.
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --service)
            SERVICE="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Ensure the --service argument was provided.
if [ -z "$SERVICE" ]; then
    log_fatal "Usage: $0 --service <service_name> [--port <port_number>]"
fi

# Route to the appropriate health check function based on the service name.
case "$SERVICE" in
    nginx)
        check_nginx
        ;;
    vllm)
        # The --port argument is mandatory for the vLLM check.
        if [ -z "$PORT" ]; then
            log_fatal "Missing --port argument for the vLLM service check."
        fi
        check_vllm "$PORT"
        ;;
    qdrant)
        check_qdrant
        ;;
    *)
        log_fatal "Unknown service specified: $SERVICE. Valid options are nginx, vllm, qdrant."
        ;;
esac