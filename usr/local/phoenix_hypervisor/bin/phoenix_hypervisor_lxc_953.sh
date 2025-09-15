#!/bin/bash

# Exit on any error
set -e

# Update package lists and install Nginx
apt-get update
apt-get install -y nginx libnginx-mod-http-js


# Add js_import and proxy_cache_path to nginx.conf
# Check if the lines already exist to ensure idempotency
if ! grep -q "js_import http.js;" /etc/nginx/nginx.conf; then
    sed -i '/http {/a \    js_import http.js;' /etc/nginx/nginx.conf
fi
if ! grep -q "proxy_cache_path /var/cache/nginx" /etc/nginx/nginx.conf; then
    sed -i '/http {/a \    proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=api_cache:10m max_size=10g inactive=60m use_temp_path=off;' /etc/nginx/nginx.conf
fi
if ! grep -q "log_format vllm_log" /etc/nginx/nginx.conf; then
    sed -i '/http {/a \    log_format vllm_log ''"''\$remote_addr - \$remote_user [\$time_local] \\"\$request\\" ''"'' ''"''\$status \$body_bytes_sent \\"\$http_referer\\" ''"'' ''"''\\"\$http_user_agent\\" \\"\$http_x_forwarded_for\\" ''"'' ''"''model:\\"\$model_name\\" upstream:\\"\$target_upstream\\""'';' /etc/nginx/nginx.conf
fi

# Copy the http.js file from the temporary directory
cp /tmp/phoenix_run/http.js /etc/nginx/http.js

# List of sites to enable
sites_to_enable=(
    "vllm_gateway"
    "n8n_proxy"
    "portainer_proxy"
    "vllm_proxy"
)

# Enable the sites idempotently
for site in "${sites_to_enable[@]}"; do
    source_file="/etc/nginx/sites-available/${site}"
    dest_file="/etc/nginx/sites-enabled/${site}"
    if [ -f "${source_file}" ]; then
        if [ ! -L "${dest_file}" ]; then
            ln -s "${source_file}" "${dest_file}"
            echo "Enabled site: ${site}"
        else
            echo "Site already enabled: ${site}"
        fi
    else
        echo "WARNING: Configuration file not found for site: ${site}"
    fi
done

# Remove default site to avoid conflicts
rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
nginx -t

# Enable and restart Nginx service
systemctl enable nginx
systemctl restart nginx

# Perform health check
if ! systemctl is-active --quiet nginx; then
    echo "Nginx service is not running."
    exit 1
fi

echo "Nginx has been installed and configured successfully."
exit 0