# CLI-Based Verification Plan for Portainer CE

**Objective:** To provide a set of command-line tools to verify the successful deployment and configuration of Portainer and its associated stacks without relying on the UI.

---

### Prerequisites

1.  The `phoenix sync all --reset-portainer` command has been run successfully.
2.  You have generated a Portainer API Key. This can be done in the UI under `Account settings` -> `API Keys`.
3.  The `jq` command-line JSON processor is installed.

---

### Verification Script

The following commands can be run from the Proxmox hypervisor to perform a full system check.

```bash
#!/bin/bash

# --- Configuration ---
# !!! IMPORTANT !!! Set your Portainer API Key here.
# You can generate this in the Portainer UI under Account -> API Keys.
PORTAINER_API_KEY="ptr_this_is_a_placeholder_replace_it"
PORTAINER_SERVER_IP="10.0.0.111" # The direct-to-container IP of the Portainer server
PORTAINER_URL="http://${PORTAINER_SERVER_IP}:9000"
EXPECTED_AGENT_COUNT=2 # Adjust this to the number of agents you expect

# --- Color Codes ---
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[1;33m'
COLOR_RESET='\033[0m'

echo -e "${COLOR_YELLOW}--- Starting Portainer CLI Verification ---${COLOR_RESET}"

# 1. Verify Portainer API Status
echo "Step 1: Checking Portainer API status..."
API_STATUS=$(curl -s -H "X-API-Key: ${PORTAINER_API_KEY}" "${PORTAINER_URL}/api/system/status" | jq -r '.Status')

if [ "$API_STATUS" == "healthy" ]; then
    echo -e "${COLOR_GREEN}PASS: Portainer API is healthy.${COLOR_RESET}"
else
    echo -e "${COLOR_RED}FAIL: Portainer API is not healthy. Status: ${API_STATUS}${COLOR_RESET}"
    exit 1
fi

# 2. Verify Endpoints (Environments)
echo -e "\nStep 2: Verifying Portainer Endpoints..."
ENDPOINTS_JSON=$(curl -s -H "X-API-Key: ${PORTAINER_API_KEY}" "${PORTAINER_URL}/api/endpoints")
AGENT_COUNT=$(echo "$ENDPOINTS_JSON" | jq '[.[] | select(.Type == 2)] | length')
UP_AGENTS=$(echo "$ENDPOINTS_JSON" | jq '[.[] | select(.Type == 2 and .Status == 1)] | length')
TCP_URLS=$(echo "$ENDPOINTS_JSON" | jq '[.[] | select(.Type == 2 and (.URL | startswith("tcp://")))] | length')

if [ "$AGENT_COUNT" -eq "$EXPECTED_AGENT_COUNT" ] && [ "$UP_AGENTS" -eq "$EXPECTED_AGENT_COUNT" ] && [ "$TCP_URLS" -eq "$EXPECTED_AGENT_COUNT" ]; then
    echo -e "${COLOR_GREEN}PASS: Found ${AGENT_COUNT}/${EXPECTED_AGENT_COUNT} agents, all are 'up' and use 'tcp://' URLs.${COLOR_RESET}"
else
    echo -e "${COLOR_RED}FAIL: Endpoint verification failed.${COLOR_RESET}"
    echo "  - Expected Agent Count: ${EXPECTED_AGENT_COUNT}"
    echo "  - Found Agent Count:    ${AGENT_COUNT}"
    echo "  - 'Up' Agent Count:     ${UP_AGENTS}"
    echo "  - Agents with tcp://:  ${TCP_URLS}"
    exit 1
fi

# 3. Verify Deployed Stacks
echo -e "\nStep 3: Verifying Deployed Stacks..."
STACKS_JSON=$(curl -s -H "X-API-Key: ${PORTAINER_API_KEY}" "${PORTAINER_URL}/api/stacks")
TOTAL_STACKS=$(echo "$STACKS_JSON" | jq 'length')
RUNNING_STACKS=$(echo "$STACKS_JSON" | jq '[.[] | select(.Status == 1)] | length') # Status 1 = Running

if [ "$TOTAL_STACKS" -gt 0 ] && [ "$TOTAL_STACKS" -eq "$RUNNING_STACKS" ]; then
    echo -e "${COLOR_GREEN}PASS: Found ${RUNNING_STACKS}/${TOTAL_STACKS} stacks, and all are running.${COLOR_RESET}"
else
    echo -e "${COLOR_RED}FAIL: Stack verification failed.${COLOR_RESET}"
    echo "  - Total Stacks Found: ${TOTAL_STACKS}"
    echo "  - Running Stacks:     ${RUNNING_STACKS}"
    exit 1
fi

echo -e "\n${COLOR_GREEN}--- All CLI Verification Steps Passed Successfully! ---${COLOR_RESET}"