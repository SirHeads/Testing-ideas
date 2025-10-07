#!/bin/bash
#
# File: generate_ssl_certs.sh
# Description: Idempotent script to generate self-signed SSL certificates for the Phoenix Hypervisor environment.
#              It now includes a --force flag to allow for the regeneration of certificates.

set -e

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PHOENIX_BASE_DIR=$(cd "${SCRIPT_DIR}/.." &> /dev/null && pwd)
source "${PHOENIX_BASE_DIR}/bin/phoenix_hypervisor_common_utils.sh"

SSL_DIR="${PHOENIX_BASE_DIR}/persistent-storage/ssl"
log_info "Ensuring central SSL directory exists at ${SSL_DIR}..."
mkdir -p "$SSL_DIR"

declare -A certs
certs=(
    ["portainer.phoenix.local"]="Phoenix Portainer"
    ["n8n.phoenix.local"]="Phoenix n8n"
    ["ollama.phoenix.local"]="Phoenix Ollama"
)

FORCE_REGENERATE=false
if [ "$1" == "--force" ]; then
    FORCE_REGENERATE=true
fi

for domain in "${!certs[@]}"; do
    org_name="${certs[$domain]}"
    key_file="${SSL_DIR}/${domain}.key"
    crt_file="${SSL_DIR}/${domain}.crt"

    if [ -f "$crt_file" ] && [ -f "$key_file" ] && [ "$FORCE_REGENERATE" = false ]; then
        log_info "Certificate for ${domain} already exists. Skipping generation."
    else
        if [ "$FORCE_REGENERATE" = true ]; then
            log_info "Forcing regeneration of certificate for ${domain}..."
        fi
        log_info "Generating self-signed certificate for ${domain}..."
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout "$key_file" \
            -out "$crt_file" \
            -subj "/C=US/ST=New York/L=New York/O=${org_name}/CN=${domain}"
    fi
done

log_info "SSL certificate setup is complete."
chmod 644 ${SSL_DIR}/*.crt
chmod 644 ${SSL_DIR}/*.key
exit 0