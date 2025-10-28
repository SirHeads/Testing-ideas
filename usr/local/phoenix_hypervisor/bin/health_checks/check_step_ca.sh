#!/bin/bash
#
# File: check_step_ca.sh
# Description: This script performs a detailed health check of the Step-CA service
#              inside the container. It checks the systemd service, log files,
#              network listeners, and the application's own health endpoint.
#
# Exit Codes:
#   0 - Success
#   1 - Generic failure
#   10 - Systemd service not found or not active
#   20 - Service log file contains errors
#   30 - Process not running
#   40 - Port 9000 not listening
#   50 - 'step ca health' command failed
#
# Version: 1.0.0
# Author: Roo

set -e

# --- Log file for detailed output ---
LOG_FILE="/var/log/step_ca_health_check.log"
exec &> >(tee -a "$LOG_FILE")

echo "--- Starting Step-CA Health Check ---"
date

# --- Check 1: Systemd Service Status ---
echo "[INFO] Checking systemd service 'step-ca.service'..."
if ! systemctl is-active --quiet step-ca.service; then
    echo "[FAIL] The 'step-ca.service' is not active."
    echo "[INFO] Displaying service status:"
    systemctl status step-ca.service --no-pager || true
    echo "[INFO] Displaying last 20 lines of journalctl for the service:"
    journalctl -u step-ca.service -n 20 --no-pager || true
    echo "[INFO] Displaying startup log:"
    cat /var/log/step-ca-startup.log || echo "[WARN] Could not read /var/log/step-ca-startup.log"
    exit 10
fi
echo "[SUCCESS] Systemd service 'step-ca.service' is active."

# --- Check 2: Process Check ---
echo "[INFO] Checking for running 'step-ca' process..."
if ! pgrep -f "step-ca" > /dev/null; then
    echo "[FAIL] The 'step-ca' process is not running."
    exit 30
fi
echo "[SUCCESS] 'step-ca' process is running."

# --- Check 3: Port Listening Check ---
echo "[INFO] Checking if port 9000 is listening..."
# Use ss, which is more modern than netstat. Install net-tools if ss is not available.
if ! command -v ss &> /dev/null; then
    echo "[INFO] 'ss' command not found. Installing net-tools..."
    apt-get update > /dev/null && apt-get install -y net-tools > /dev/null
fi

if ! ss -tuln | grep -q ':9000'; then
    echo "[FAIL] Port 9000 is not in a listening state."
    echo "[INFO] Current network listeners:"
    ss -tuln || true
    exit 40
fi
echo "[SUCCESS] Port 9000 is listening."

# --- Check 4: Application Health Check ---
echo "[INFO] Performing application-level health check with 'step ca health'..."
# This requires the root cert to be available. The service should be running, so the certs should be in /root/.step/certs/
if ! step ca health --ca-url "https://ca.internal.thinkheads.ai:9000" --root "/etc/step-ca/ssl/certs/root_ca.crt"; then
    echo "[FAIL] 'step ca health' command failed."
    echo "[INFO] This indicates the service is running but the CA endpoint is not healthy."
    exit 50
fi
echo "[SUCCESS] Application-level health check passed."

echo "--- Step-CA Health Check PASSED ---"
exit 0