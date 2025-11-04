#!/bin/bash
set -e

echo "--- Portainer Authentication Test ---"

# --- Configuration ---
CONFIG_FILE="/usr/local/phoenix_hypervisor/etc/phoenix_hypervisor_config.json"
PORTAINER_HOSTNAME="portainer.internal.thinkheads.ai"
GATEWAY_URL="https://${PORTAINER_HOSTNAME}"
CA_CERT_PATH="/mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_root_ca.crt"

# --- 1. Read Credentials ---
echo "Reading credentials from ${CONFIG_FILE}..."
USERNAME=$(jq -r '.portainer_api.admin_user' "$CONFIG_FILE")
PASSWORD=$(jq -r '.portainer_api.admin_password' "$CONFIG_FILE")

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo "ERROR: Could not read username or password from config file."
    exit 1
fi

echo "Username found: ${USERNAME}"
echo "Password found: [REDACTED]"

# --- 2. Construct Payload ---
AUTH_PAYLOAD=$(jq -n --arg user "$USERNAME" --arg pass "$PASSWORD" '{username: $user, password: $pass}')
echo "Constructed authentication payload."

# --- 3. Execute Authentication Request ---
echo "Attempting to authenticate with Portainer API at ${GATEWAY_URL}..."
echo "--------------------------------------------------"

RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    --cacert "$CA_CERT_PATH" \
    --resolve "${PORTAINER_HOSTNAME}:443:10.0.0.153" \
    -d "$AUTH_PAYLOAD" \
    "${GATEWAY_URL}/api/auth" --verbose)

# --- 4. Analyze Response ---
echo "--------------------------------------------------"
HTTP_STATUS=$(echo -e "$RESPONSE" | tail -n1 | sed -n 's/.*HTTP_STATUS://p')
BODY=$(echo -e "$RESPONSE" | sed '$d')

echo "API Response Code: ${HTTP_STATUS}"
echo "API Response Body: ${BODY}"

if [[ "$HTTP_STATUS" -ge 200 && "$HTTP_STATUS" -lt 300 ]]; then
    echo "---"
    echo "SUCCESS: Authentication successful. A JWT was received."
    echo "This indicates the credentials in your config file ARE CORRECT."
    exit 0
elif [[ "$HTTP_STATUS" -eq 422 ]]; then
    echo "---"
    echo "FAILURE: Authentication failed with HTTP 422."
    echo "The response body '{\"message\":\"Invalid credentials\",\"details\":\"Unauthorized\"}' confirms that the Portainer service is rejecting the username/password combination provided by your config file."
    exit 1
else
    echo "---"
    echo "FAILURE: An unexpected error occurred. The status code was ${HTTP_STATUS}."
    echo "This might indicate a networking, firewall, or certificate issue rather than a password problem."
    exit 1
fi