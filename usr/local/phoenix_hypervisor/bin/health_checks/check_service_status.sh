#!/bin/bash
#
# File: check_service_status.sh
# Description: A centralized script to check the health of various services.
#

# --- Source common utilities ---
# The common_utils.sh script provides shared functions for logging, error handling, etc.
source "/usr/local/phoenix_hypervisor/bin/phoenix_hypervisor_common_utils.sh"

# --- Function Definitions ---

check_nginx() {
    if curl --fail --silent http://localhost > /dev/null; then
        log_info "NGINX is responsive."
        return 0
    else
        log_error "NGINX is not responding."
        return 1
    fi
}

check_vllm() {
    local port="$1"
    if ! lsof -i:"$port" -sTCP:LISTEN -t >/dev/null; then
        log_error "No process is listening on port $port."
        exit 1
    fi
    if curl --fail --silent http://localhost:"$port"/health > /dev/null; then
        log_info "vLLM on port $port is healthy."
        return 0
    else
        log_error "vLLM on port $port is not responding."
        return 1
    fi
}

check_qdrant() {
    if curl --fail --silent http://localhost/qdrant/healthz > /dev/null; then
        log_info "Qdrant is healthy."
        return 0
    else
        log_error "Qdrant is not responding."
        return 1
    fi
}

# --- Main Script Logic ---

SERVICE=""
PORT=""

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

if [ -z "$SERVICE" ]; then
    log_fatal "Usage: $0 --service <service_name> [--port <port_number>]"
fi

case "$SERVICE" in
    nginx)
        check_nginx
        ;;
    vllm)
        if [ -z "$PORT" ]; then
            log_fatal "Missing --port for vLLM service check."
        fi
        check_vllm "$PORT"
        ;;
    qdrant)
        check_qdrant
        ;;
    *)
        log_fatal "Unknown service: $SERVICE"
        ;;
esac