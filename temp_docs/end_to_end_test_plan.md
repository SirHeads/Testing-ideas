# End-to-End System Verification Plan

This document contains a comprehensive, self-contained shell script designed to verify the health and proper functioning of the entire Phoenix Hypervisor environment. It consolidates the key checks from the individual diagnostic plans into a single, executable script.

## Objective

To provide a repeatable and automated way to test the core components of the system, including DNS, certificate management, the Nginx gateway, and the Portainer API endpoint.

## Verification Script

The following script can be copied and executed on the Proxmox host to perform the end-to-end verification.

```bash
#!/bin/bash

# --- Color Codes for Output ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Helper Functions ---
print_header() {
    echo -e "\n${YELLOW}--- $1 ---${NC}"
}

print_success() {
    echo -e "${GREEN}SUCCESS:${NC} $1"
}

print_failure() {
    echo -e "${RED}FAILURE:${NC} $1"
}

# --- Verification Starts ---

print_header "Phase 1: DNS Resolution Verification"
echo "--> Verifying dnsmasq service on host..."
if systemctl is-active --quiet dnsmasq; then
    print_success "dnsmasq service is active."
else
    print_failure "dnsmasq service is not running."
fi

echo "--> Testing host resolution for portainer.internal.thinkheads.ai..."
if dig @127.0.0.1 portainer.internal.thinkheads.ai | grep -A1 "ANSWER SECTION" | grep -q "10.0.0.153"; then
    print_success "Host correctly resolved portainer.internal.thinkheads.ai to the Nginx gateway."
else
    print_failure "Host failed to resolve portainer.internal.thinkheads.ai."
fi

print_header "Phase 2: Certificate Verification"
echo "--> Verifying Step-CA service health (LXC 103)..."
if pct exec 103 -- systemctl is-active --quiet step-ca; then
    print_success "Step-CA service is active in LXC 103."
else
    print_failure "Step-CA service is not running in LXC 103."
fi

echo "--> Verifying Nginx certificate and key readability (LXC 101)..."
if pct exec 101 -- sudo -u www-data cat /etc/nginx/ssl/nginx.internal.thinkheads.ai.key > /dev/null 2>&1; then
    print_success "Nginx key is readable by www-data user."
else
    print_failure "Nginx key is NOT readable by www-data user. Check permissions on /mnt/pve/quickOS/lxc-persistent-data/101/ssl/"
fi

print_header "Phase 3: Nginx Gateway and End-to-End Connectivity"
echo "--> Verifying Nginx service health (LXC 101)..."
if pct exec 101 -- systemctl is-active --quiet nginx; then
    print_success "Nginx service is active in LXC 101."
else
    print_failure "Nginx service is not running in LXC 101."
fi

echo "--> Performing end-to-end test of Portainer API via gateway..."
CURL_OUTPUT=$(curl --resolve portainer.internal.thinkheads.ai:443:10.0.0.153 \
                   --cacert /mnt/pve/quickOS/lxc-persistent-data/103/ssl/phoenix_root_ca.crt \
                   --silent \
                   https://portainer.internal.thinkheads.ai/api/system/status)

if echo "$CURL_OUTPUT" | grep -q "InstanceID"; then
    print_success "Successfully retrieved Portainer status via gateway (Already Initialized)."
elif echo "$CURL_OUTPUT" | grep -q "No administrator account found"; then
    print_success "Successfully retrieved Portainer status via gateway (Ready for Init)."
else
    print_failure "Failed to retrieve Portainer status via gateway. Output: $CURL_OUTPUT"
fi

echo -e "\n${YELLOW}--- Verification Complete ---${NC}"
