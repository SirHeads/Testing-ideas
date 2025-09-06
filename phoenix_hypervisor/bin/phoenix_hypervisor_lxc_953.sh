#!/bin/bash
#
# File: phoenix_hypervisor_lxc_953.sh
# Description: Manages the deployment and configuration of an Nginx API Gateway within an LXC container (CTID 953).
#              This script handles the installation of Nginx, dynamic generation of Nginx configuration
#              as a reverse proxy to a backend service, and management of the Nginx systemd service.
#              It also includes health checks to ensure the gateway is operational.
# Dependencies: phoenix_hypervisor_common_utils.sh (sourced), apt-get, nginx, pct, systemctl, curl, journalctl.
# Inputs:
#   $1 (CTID) - The container ID for the Nginx API Gateway.
#   backend_ip (hardcoded as 10.0.0.151) - The IP address of the backend service to proxy to.
#   backend_port (hardcoded as 8000) - The port of the backend service.
# Outputs:
#   Nginx installation logs, Nginx configuration files, systemd service management output,
#   HTTP response codes from health checks, log messages to stdout and MAIN_LOG_FILE,
#   exit codes indicating success or failure.
# Version: 1.0.0
# Author: Phoenix Hypervisor Team

# --- Source common utilities ---
source "$(dirname "$0")/phoenix_hypervisor_common_utils.sh"

# --- Script Variables ---
CTID=""
SERVICE_NAME="nginx"
NGINX_CONF_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
NGINX_DEFAULT_CONF="default"

# =====================================================================================
# Function: parse_arguments
# Description: Parses the CTID from command-line arguments.
# =====================================================================================
# =====================================================================================
# Function: parse_arguments
# Description: Parses command-line arguments to extract the Container ID (CTID).
# Arguments:
#   $1 - The Container ID (CTID) for the LXC container.
# Returns:
#   Exits with status 2 if no CTID is provided or if too many arguments are given.
# =====================================================================================
parse_arguments() {
    # Check if exactly one argument (CTID) is provided
    if [ "$#" -ne 1 ]; then
        log_error "Usage: $0 <CTID>"
        exit_script 2
    fi
    CTID="$1" # Assign the first argument to CTID
    log_info "Executing application runner for CTID: $CTID"
}

# =====================================================================================
# Function: install_nginx
# Description: Installs the Nginx web server inside the specified LXC container.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None. Exits with a fatal error if apt-get commands fail.
# =====================================================================================
install_nginx() {
    log_info "Installing Nginx in CTID: $CTID..."
    pct_exec "$CTID" apt-get update # Update package lists
    pct_exec "$CTID" apt-get install -y nginx # Install Nginx
    log_info "Nginx installation complete."
}

# =====================================================================================
# Function: configure_nginx
# Description: Configures Nginx as a reverse proxy within the specified LXC container.
#              It generates an Nginx server block configuration to proxy requests
#              to a hardcoded backend IP and port, writes it to a file, and enables
#              the site.
# Arguments:
#   None (uses global CTID, NGINX_CONF_DIR, NGINX_ENABLED_DIR, NGINX_DEFAULT_CONF).
# Returns:
#   Exits with a fatal error if writing the config file or enabling the site fails.
# =====================================================================================
configure_nginx() {
    log_info "Configuring Nginx as a reverse proxy in CTID: $CTID..."

    # --- Retrieve backend service IP from central config (example: vllm-granite-embed) ---
    # For this example, we'll hardcode a backend, but in a real scenario,
    # you might fetch this dynamically or from the config.
    # Hardcoded backend IP and port for the vLLM embedding server
    local backend_ip="10.0.0.151" # Example: IP of vllm-granite-embed
    local backend_port="8000"

    local nginx_config_content
    nginx_config_content=$(printf '%s\n' \
        "server {" \
        "    listen 80 default_server;" \
        "    listen [::]:80 default_server;" \
        "" \
        "    root /var/www/html;" \
        "    index index.html index.htm index.nginx-debian.html;" \
        "" \
        "    server_name _;" \
        "" \
        "    location / {" \
        "        proxy_pass http://${backend_ip}:${backend_port};" \
        "        proxy_set_header Host \$host;" \
        "        proxy_set_header X-Real-IP \$remote_addr;" \
        "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" \
        "        proxy_set_header X-Forwarded-Proto \$scheme;" \
        "    }" \
        "}" \
    )

    # --- Write the Nginx configuration file ---
    # Define the path for the Nginx configuration file
    local config_file_path="${NGINX_CONF_DIR}/${NGINX_DEFAULT_CONF}"
    log_info "Writing Nginx configuration to $config_file_path in CTID $CTID..."
    # Write the Nginx configuration content to the file inside the container
    if ! echo "${nginx_config_content}" | pct exec "$CTID" -- tee "${config_file_path}" > /dev/null; then
        log_fatal "Failed to write Nginx configuration file in CTID $CTID."
    fi

    # --- Enable the Nginx site ---
    # Create a symbolic link to enable the Nginx site
    log_info "Enabling Nginx site: ${NGINX_DEFAULT_CONF}..."
    if ! pct_exec "$CTID" ln -sf "${NGINX_CONF_DIR}/${NGINX_DEFAULT_CONF}" "${NGINX_ENABLED_DIR}/${NGINX_DEFAULT_CONF}"; then
        log_fatal "Failed to enable Nginx site in CTID $CTID."
    fi

    # --- Remove default Nginx welcome page symlink if it exists ---
    # Remove the default Nginx welcome page symlink if it exists to avoid conflicts
    log_info "Removing default Nginx welcome page symlink..."
    if pct_exec "$CTID" test -L "${NGINX_ENABLED_DIR}/default"; then
        pct_exec "$CTID" rm "${NGINX_ENABLED_DIR}/default" # Remove the symlink
    fi

    log_info "Nginx configuration complete."
}

# =====================================================================================
# Function: manage_nginx_service
# Description: Manages the Nginx systemd service within the specified LXC container.
#              This includes reloading the systemd daemon, enabling the service to start
#              on boot, and starting/restarting the service. It also provides error
#              logging and retrieves journalctl logs on service startup failure.
# Arguments:
#   None (uses global CTID and SERVICE_NAME).
# Returns:
#   Exits with a fatal error if systemd daemon reload, service enable, or service start fails.
# =====================================================================================
manage_nginx_service() {
    log_info "Managing the $SERVICE_NAME service in CTID $CTID..."

    # --- Reload the systemd daemon to recognize any changes ---
    # Reload the systemd daemon to recognize any changes to service files
    log_info "Reloading systemd daemon..."
    if ! pct_exec "$CTID" systemctl daemon-reload; then
        log_fatal "Failed to reload systemd daemon in CTID $CTID."
    fi

    # --- Enable the service to start on boot ---
    # Enable the Nginx service to ensure it starts automatically on container boot
    log_info "Enabling $SERVICE_NAME service..."
    if ! pct_exec "$CTID" systemctl enable "$SERVICE_NAME"; then
        log_fatal "Failed to enable $SERVICE_NAME service in CTID $CTID."
    fi

    # --- Start/Restart the service ---
    # Restart the Nginx service to apply new configurations
    log_info "Restarting $SERVICE_NAME service..."
    if ! pct_exec "$CTID" systemctl restart "$SERVICE_NAME"; then
        log_error "$SERVICE_NAME service failed to start. Retrieving logs..."
        local journal_logs
        # If the service fails to start, retrieve and log the latest journalctl logs for diagnosis
        journal_logs=$(pct_exec "$CTID" journalctl -u "$SERVICE_NAME" --no-pager -n 50)
        log_error "Recent logs for $SERVICE_NAME:"
        log_plain_output "$journal_logs" # Log the retrieved journal entries
        log_fatal "Failed to start $SERVICE_NAME service. See logs above for details."
    fi

    log_info "$SERVICE_NAME service started successfully."
}

# =====================================================================================
# Function: perform_health_check
# Description: Performs a health check on the Nginx API Gateway within the specified
#              LXC container to ensure it is running and correctly routing requests.
#              It retries multiple times with a delay.
# Arguments:
#   None (uses global CTID and SERVICE_NAME).
# Returns:
#   0 on successful health check (HTTP 200 response), exits with a fatal error if
#   the health check fails after all attempts.
# =====================================================================================
perform_health_check() {
    log_info "Performing health check on the Nginx API Gateway..."
    local max_attempts=12 # Maximum number of health check attempts
    local attempt=0 # Current attempt counter
    local interval=10 # Delay between attempts in seconds
    local gateway_url="http://localhost" # Nginx listens on port 80 by default for this configuration

    # Loop to perform health checks until successful or max attempts reached
    while [ "$attempt" -lt "$max_attempts" ]; do
        attempt=$((attempt + 1)) # Increment attempt counter
        log_info "Health check attempt $attempt/$max_attempts..."
        
        local response_code
        # Execute curl command inside the container to check the Nginx gateway,
        # capturing only the HTTP response code.
        response_code=$(pct exec "$CTID" -- curl -s -o /dev/null -w "%{http_code}" "$gateway_url" || echo "CURL_ERROR")

        # Check the response code from the curl command
        if [ "$response_code" == "CURL_ERROR" ]; then
            log_info "Gateway not ready yet (curl command failed, likely connection refused). Retrying in $interval seconds..."
            sleep "$interval" # Wait before retrying
            continue # Continue to the next attempt
        elif [ "$response_code" == "200" ]; then
            log_info "Health check passed! Nginx is responsive and serving content."
            return 0 # Health check successful
        else
            log_info "Nginx returned HTTP status code: $response_code. Retrying in $interval seconds..."
            sleep "$interval" # Wait before retrying
        fi
    done

    log_error "Health check failed after $max_attempts attempts. Nginx is not responsive."
    log_error "Retrieving latest service logs for diagnosis..."
    log_error "Recent logs for $SERVICE_NAME:"
    pct_exec "$CTID" journalctl -u "$SERVICE_NAME" --no-pager -n 50 | log_plain_output
    log_fatal "Nginx service health check failed."
}

# =====================================================================================
# Function: display_connection_info
# Description: Displays the final connection details for the Nginx API Gateway,
#              including its IP address and the backend it is proxying to.
# Arguments:
#   None (uses global CTID).
# Returns:
#   None.
# =====================================================================================
display_connection_info() {
    local ip_address
    ip_address=$(jq_get_value "$CTID" ".network_config.ip" | cut -d'/' -f1) # Extract IP address from network config

    log_info "============================================================"
    log_info "Nginx API Gateway is now running and fully operational."
    log_info "============================================================"
    log_info "Connection Details:"
    log_info "  IP Address: $ip_address"
    log_info "  Port: 80 (HTTP)"
    log_info ""
    log_info "Nginx is configured to reverse proxy requests to http://10.0.0.151:8000"
    log_info "============================================================"
}

# =====================================================================================
# Function: main
# Description: Main entry point for the Nginx API Gateway application runner script.
#              Orchestrates the entire process of installing, configuring, starting,
#              and verifying the Nginx service within an LXC container.
# Arguments:
#   $@ - All command-line arguments passed to the script.
# Returns:
#   Exits with status 0 on successful completion, or a non-zero status on failure
#   (handled by exit_script).
# =====================================================================================
main() {
    parse_arguments "$@" # Parse command-line arguments
    install_nginx # Install Nginx
    configure_nginx # Configure Nginx as a reverse proxy
    manage_nginx_service # Enable and start the Nginx service
    perform_health_check # Perform a health check on the Nginx gateway
    display_connection_info # Display connection information to the user
    exit_script 0 # Exit successfully
}

main "$@"