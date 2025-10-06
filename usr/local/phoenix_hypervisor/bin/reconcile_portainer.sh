#!/bin/bash
#
# File: reconcile_portainer.sh
# Description: This script triggers the Portainer reconciliation process. It finds the primary
#              Portainer server VM and executes the portainer_api_setup.sh script inside it.
#              This ensures that all agent endpoints and Docker stacks are kept in sync with
#              the hypervisor's configuration.

set -e

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/.." &> /dev/null && pwd)

source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

main() {
    log_info "Starting Portainer reconciliation process..."

    local primary_vmid
    primary_vmid=$(jq -r '.vms[] | select(.portainer_role == "primary") | .vmid' "$VM_CONFIG_FILE")

    if [ -z "$primary_vmid" ] || [ "$primary_vmid" == "null" ]; then
        log_warn "No primary Portainer VM found in the configuration. Skipping reconciliation."
        exit 0
    fi

    log_info "Found primary Portainer VM with ID: $primary_vmid"

    # The API setup script is expected to be on the persistent volume, copied there by the feature install script.
    local script_path_in_vm="/persistent-storage/.phoenix_scripts/portainer_api_setup.sh"

    log_info "Executing Portainer API setup script asynchronously inside VM $primary_vmid..."
    
    local log_file_in_vm="/var/log/phoenix_portainer_reconciliation.log"
    local exit_code_file_in_vm="/tmp/phoenix_reconciliation_exit_code"

    # Remove the old exit code file to ensure a clean run
    qm guest exec "$primary_vmid" -- /bin/bash -c "rm -f $exit_code_file_in_vm" >/dev/null 2>&1

    # Execute the script in the background, writing the exit code to a file upon completion
    local exec_command="nohup /bin/bash -c 'bash $script_path_in_vm; echo \$? > $exit_code_file_in_vm' > $log_file_in_vm 2>&1 &"
    if ! qm guest exec "$primary_vmid" -- /bin/bash -c "$exec_command"; then
        log_error "Failed to start Portainer API setup script in VM $primary_vmid. Reconciliation failed."
        exit 1
    fi

    log_info "Reconciliation script started. Tailing log file: $log_file_in_vm"

    # Monitor the process and stream the log
    local timeout=1800 # 30 minutes timeout
    local start_time=$SECONDS
    local last_log_line=0

    while true; do
        # Stream new log content
        local new_log_output
        new_log_output=$(qm guest exec "$primary_vmid" -- /bin/bash -c "tail -n +$((last_log_line + 1)) $log_file_in_vm" 2>/dev/null)
        local new_log_content
        new_log_content=$(echo "$new_log_output" | jq -r '."out-data" // ""')
        if [ -n "$new_log_content" ]; then
            echo -e "$new_log_content"
            new_lines_count=$(echo "$new_log_content" | wc -l | tr -d '[:space:]')
            last_log_line=$((last_log_line + new_lines_count))
        fi

        # Check if the exit code file exists
        local exit_code_output
        exit_code_output=$(qm guest exec "$primary_vmid" -- /bin/bash -c "cat $exit_code_file_in_vm" 2>/dev/null)
        local exit_code
        exit_code=$(echo "$exit_code_output" | jq -r '."out-data" // ""' | tr -d '[:space:]')

        if [ -n "$exit_code" ]; then
            if [ "$exit_code" -eq 0 ]; then
                log_success "Reconciliation script completed successfully."
                break
            else
                log_fatal "Reconciliation script failed with exit code $exit_code."
            fi
        fi

        # Check for timeout
        if (( SECONDS - start_time > timeout )); then
            log_fatal "Timeout reached while waiting for reconciliation script to complete."
        fi

        sleep 5
    done

    log_success "Portainer reconciliation process completed successfully."
}

main