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
if ! grep -q "log_format main" /etc/nginx/nginx.conf; then
    sed -i '/http {/a \    log_format main ''"''\$remote_addr - \$remote_user [\$time_local] \\"\$request\\" ''"'' ''"''\$status \$body_bytes_sent \\"\$http_referer\\" ''"'' ''"''\\"\$http_user_agent\\" \\"\$http_x_forwarded_for\\"''"'';' /etc/nginx/nginx.conf
fi

# Copy the http.js file from the temporary directory
cp /tmp/phoenix_run/http.js /etc/nginx/http.js

# Nginx sites are mounted from the host, so we only need to enable them.

# List of sites to enable
# Generate the gateway configuration dynamically
GATEWAY_CONFIG="/etc/nginx/sites-available/vllm_gateway"
echo "Generating NGINX gateway configuration at $GATEWAY_CONFIG"

# Clear the existing configuration file
> "$GATEWAY_CONFIG"

# Start with the static parts of the configuration
cat > "$GATEWAY_CONFIG" << EOL
# /etc/nginx/nginx.conf

# Define a javascript function to extract the model from the JSON body.
js_set \$model_name http.get_model;

# Define a custom log format to include model and upstream information
log_format vllm_log '"\$remote_addr - \$remote_user [\$time_local] \"\$request\" '
                    '\$status \$body_bytes_sent \"\$http_referer\" '
                    '\"\$http_user_agent\" \"\$http_x_forwarded_for\" '
                    'model:\"\$model_name\" upstream:\"\$target_upstream\"';
log_format vllm_logs '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                     '\$status \$body_bytes_sent "\$http_referer" '
                     '"\$http_user_agent" "\$http_x_forwarded_for" '
                     'model:"\$model_name" upstream:"\$target_upstream"';

EOL

# Dynamically generate the upstream blocks
for ctid in $(jq -r '.lxc_configs | keys[]' /tmp/phoenix_run/phoenix_lxc_configs.json); do
    name=$(jq -r ".lxc_configs[\"$ctid\"].name" /tmp/phoenix_run/phoenix_lxc_configs.json)
    ip=$(jq -r ".lxc_configs[\"$ctid\"].network_config.ip" /tmp/phoenix_run/phoenix_lxc_configs.json | cut -d'/' -f1)
    ports=$(jq -r ".lxc_configs[\"$ctid\"].ports[]?" /tmp/phoenix_run/phoenix_lxc_configs.json)

    if [ -n "$ports" ]; then
        for port_mapping in $ports; do
            host_port=$(echo "$port_mapping" | cut -d':' -f1)
            container_port=$(echo "$port_mapping" | cut -d':' -f2)
            
            # Sanitize the name for use in the upstream block
            sanitized_name=$(echo "$name" | tr -c '[:alnum:]' '_')
            
            echo "upstream ${sanitized_name}_service_${host_port} {" >> "$GATEWAY_CONFIG"
            echo "    server $ip:$host_port;" >> "$GATEWAY_CONFIG"
            echo "}" >> "$GATEWAY_CONFIG"
        done
    fi
done

# Add the rest of the static configuration
cat >> "$GATEWAY_CONFIG" << EOL

# Map the model name to the correct upstream service.
map \$model_name \$target_upstream {
    default embedding_service; # Default to the embedding model for safety
    "granite" qwen_service;
    "embedding" embedding_service;
}

server {
    listen 80;
    server_name api.yourdomain.com 10.0.0.153;

    # Set the access log to use the custom format
    access_log /var/log/nginx/vllm_access.log vllm_logs;

    # Common proxy settings to avoid repetition
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    location /v1/chat/completions {
        proxy_pass http://\$target_upstream;
    }

    location /v1/completions {
        proxy_pass http://\$target_upstream;
    }

    location /v1/embeddings {
        proxy_pass http://\$target_upstream;
    }
EOL

# Dynamically generate the location blocks
for ctid in $(jq -r '.lxc_configs | keys[]' /tmp/phoenix_run/phoenix_lxc_configs.json); do
    name=$(jq -r ".lxc_configs[\"$ctid\"].name" /tmp/phoenix_run/phoenix_lxc_configs.json)
    ports=$(jq -r ".lxc_configs[\"$ctid\"].ports[]?" /tmp/phoenix_run/phoenix_lxc_configs.json)

    if [ -n "$ports" ]; then
        # Sanitize the name for use in the location block
        sanitized_name=$(echo "$name" | tr -c '[:alnum:]' '_')
        
        for port_mapping in $ports; do
            host_port=$(echo "$port_mapping" | cut -d':' -f1)
            
            echo "    location /${sanitized_name}/${host_port}/ {" >> "$GATEWAY_CONFIG"
            echo "        rewrite ^/${sanitized_name}/${host_port}/?(.*)$ /\$1 break;" >> "$GATEWAY_CONFIG"
            echo "        proxy_pass http://${sanitized_name}_service_${host_port};" >> "$GATEWAY_CONFIG"
            echo "    }" >> "$GATEWAY_CONFIG"
        done
    fi
done

# Add the closing brace for the server block
echo "}" >> "$GATEWAY_CONFIG"

# Enable the gateway
rm -f /etc/nginx/sites-enabled/vllm_gateway
ln -s /etc/nginx/sites-available/vllm_gateway /etc/nginx/sites-enabled/vllm_gateway

# Remove default site to avoid conflicts
rm -f /etc/nginx/sites-enabled/default

# Create SSL directory
mkdir -p /etc/nginx/ssl

# Generate self-signed certificates for the proxy sites
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/n8n.phoenix.local.key \
    -out /etc/nginx/ssl/n8n.phoenix.local.crt \
    -subj "/C=US/ST=New York/L=New York/O=Phoenix/CN=n8n.phoenix.local"

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/portainer.phoenix.local.key \
    -out /etc/nginx/ssl/portainer.phoenix.local.crt \
    -subj "/C=US/ST=New York/L=New York/O=Phoenix/CN=portainer.phoenix.local"

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/ollama.phoenix.local.key \
    -out /etc/nginx/ssl/ollama.phoenix.local.crt \
    -subj "/C=US/ST=New York/L=New York/O=Phoenix/CN=ollama.phoenix.local"

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