#!/bin/bash

MAIN_LOG_FILE="/var/log/phoenix_hypervisor.log"

log_debug() {
    if [ "$PHOENIX_DEBUG" == "true" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] phoenix_hypervisor_lxc_common_loghelpers.sh: $*" | tee -a "$MAIN_LOG_FILE"
    fi
}

log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] phoenix_hypervisor_lxc_common_loghelpers.sh: $*" | tee -a "$MAIN_LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] phoenix_hypervisor_lxc_common_loghelpers.sh: $*" | tee -a "$MAIN_LOG_FILE" >&2
}