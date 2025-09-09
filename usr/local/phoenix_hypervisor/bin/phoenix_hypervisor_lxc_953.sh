#!/bin/bash

# Exit on any error
set -e

# Update package lists and install Nginx
apt-get update
apt-get install -y nginx

# Configure Nginx reverse proxy
cat <<'EOF' > /etc/nginx/sites-available/vllm_proxy
upstream vllm_backend {
    server 10.0.0.151:8000;
}

server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://vllm_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_cache api_cache;
        proxy_cache_valid 200 302 10m;
        proxy_cache_valid 404 1m;
        proxy_cache_key "$scheme$request_method$host$request_uri";
        add_header X-Proxy-Cache $upstream_cache_status;
    }
}
EOF

# Add proxy_cache_path to nginx.conf
# Check if the line already exists to ensure idempotency
if ! grep -q "proxy_cache_path /var/cache/nginx" /etc/nginx/nginx.conf; then
    sed -i '/http {/a \    proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=api_cache:10m max_size=10g inactive=60m use_temp_path=off;' /etc/nginx/nginx.conf
fi

# Enable the site
if [ ! -L /etc/nginx/sites-enabled/vllm_proxy ]; then
    ln -s /etc/nginx/sites-available/vllm_proxy /etc/nginx/sites-enabled/
fi

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