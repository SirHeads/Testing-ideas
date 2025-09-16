# Host Prerequisite Check Code

This file contains the shell script code to be inserted into `phoenix_orchestrator.sh` to perform the host prerequisite check for `idmap` configuration.

## New Function: `ensure_host_idmap_configured`

This function should be placed before the `ensure_container_configured` function in `phoenix_orchestrator.sh`.

```bash
# =====================================================================================
# Function: ensure_host_idmap_configured
# Description: Checks for the existence of /etc/subuid and /etc/subgid files, which are
#              critical for unprivileged container user namespace mapping. If the files
#              are missing, it creates them with a default mapping for the root user.
#              This is a mandatory pre-flight check.
# Arguments:
#   None.
# Returns:
#   None. Exits with a fatal error if file creation fails.
# =====================================================================================
ensure_host_idmap_configured() {
    log_info "Performing host prerequisite check for idmap configuration..."
    local subuid_file="/etc/subuid"
    local subgid_file="/etc/subgid"
    local required_content="root:100000:65536"
    local files_configured=true

    # Check /etc/subuid
    if [ ! -f "$subuid_file" ]; then
        log_warn "File not found: $subuid_file. Creating it now."
        if ! echo "$required_content" > "$subuid_file"; then
            log_fatal "Failed to create and configure $subuid_file."
        fi
        log_info "$subuid_file created successfully."
        files_configured=false
    else
        log_info "$subuid_file found."
    fi

    # Check /etc/subgid
    if [ ! -f "$subgid_file" ]; then
        log_warn "File not found: $subgid_file. Creating it now."
        if ! echo "$required_content" > "$subgid_file"; then
            log_fatal "Failed to create and configure $subgid_file."
        fi
        log_info "$subgid_file created successfully."
        files_configured=false
    else
        log_info "$subgid_file found."
    fi

    if [ "$files_configured" = true ]; then
        log_info "Host idmap configuration check passed."
    fi
}
```

## Function Call

The following line should be added to the `main` function, right after the `setup_logging` call.

```bash
    setup_logging
    ensure_host_idmap_configured # ADD THIS LINE
    exec &> >(tee -a "$LOG_FILE") # Redirect stdout/stderr to screen and log file