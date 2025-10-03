#!/bin/bash
#
# File: phoenix_hypervisor_lxc_101.sh
# Description: Self-contained setup for Nginx API Gateway in LXC 101. Copies configs from /tmp/phoenix_run/, generates certs if needed, and starts the service with NJS module support.

set -e

# --- Package Installation ---
echo "Updating package lists and installing Nginx and the NJS module..."
apt-get update
apt-get install -y nginx libnginx-mod-http-js

# The libnginx-mod-http-js package automatically creates a symlink in
# /etc/nginx/modules-enabled/ to load the module.

# --- Config Extraction from Tarball ---
TMP_DIR="/tmp/phoenix_run"
CONFIG_TARBALL="${TMP_DIR}/nginx_configs.tar.gz"

echo "Extracting Nginx configurations from tarball..."
tar -xzf "$CONFIG_TARBALL" -C "$TMP_DIR" || { echo "Failed to extract Nginx config tarball." >&2; exit 1; }

# --- Config Copying from Temp Dir ---
SITES_AVAILABLE_DIR="/etc/nginx/sites-available"
SITES_ENABLED_DIR="/etc/nginx/sites-enabled"
SCRIPTS_DIR="/etc/nginx/scripts"
SSL_DIR="/etc/nginx/ssl"

# Create directories
mkdir -p $SITES_AVAILABLE_DIR $SITES_ENABLED_DIR $SCRIPTS_DIR $SSL_DIR

# Copy files (assume pushed by lxc-manager.sh)
cp $TMP_DIR/sites-available/* $SITES_AVAILABLE_DIR/ || { echo "Config files missing in $TMP_DIR." >&2; exit 1; }
cp $TMP_DIR/scripts/* $SCRIPTS_DIR/ || { echo "JS script missing in $TMP_DIR." >&2; exit 1; }

# Link enabled sites
ln -sf $SITES_AVAILABLE_DIR/vllm_gateway $SITES_ENABLED_DIR/vllm_gateway

# Remove default site
rm -f $SITES_ENABLED_DIR/default

# Generate self-signed certs if missing
if [ ! -f "$SSL_DIR/portainer.phoenix.local.crt" ]; then
    echo "Generating self-signed certificates..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$SSL_DIR/n8n.phoenix.local.key" \
        -out "$SSL_DIR/n8n.phoenix.local.crt" \
        -subj "/C=US/ST=New York/L=New York/O=Phoenix/CN=n8n.phoenix.local"

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$SSL_DIR/portainer.phoenix.local.key" \
        -out "$SSL_DIR/portainer.phoenix.local.crt" \
        -subj "/C=US/ST=New York/L=New York/O=Phoenix/CN=portainer.phoenix.local"

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$SSL_DIR/ollama.phoenix.local.key" \
        -out "$SSL_DIR/ollama.phoenix.local.crt" \
        -subj "/C=US/ST=New York/L=New York/O=Phoenix/CN=ollama.phoenix.local"
else
    echo "Certificates already exist. Skipping generation."
fi

# Remove invalid js_include from nginx.conf if present
sed -i '/js_include/d' /etc/nginx/nginx.conf

# Add NJS module configuration
echo "Adding NJS module configuration..."
cat > /etc/nginx/conf.d/njs.conf << 'EOF'
js_import http from /etc/nginx/scripts/http.js;
EOF

# Overwrite vllm_gateway to ensure JS module usage
cat > /etc/nginx/sites-available/vllm_gateway << 'EOF'
# Nginx API Gateway configuration for various backend AI and management services.

upstream embedding_service { server 10.0.0.141:8000; }
upstream qwen_service { server 10.0.0.150:8000; }
upstream qdrant_service { server 10.0.0.152:6333; }
upstream n8n_service { server 10.0.0.154:5678; }
upstream open_webui_service { server 10.0.0.156:8080; }
upstream ollama_service { server 10.0.0.155:11434; }
upstream llamacpp_service { server 10.0.0.157:8081; }
upstream portainer_service { server 10.0.0.101:9443; }

server {
    listen 80;
    server_name api.yourdomain.com 10.0.0.153;

    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # Use JS module to process requests for /v1/chat/completions
    location /v1/chat/completions {
        js_content http.get_model;  # Invoke the get_model function from http.js
        proxy_pass http://qwen_service;
    }

    location /v1/completions {
        proxy_pass http://qwen_service;
    }

    location /v1/embeddings {
        proxy_pass http://embedding_service;
    }

    location /qdrant/ {
        proxy_pass http://qdrant_service/;
    }

    location /n8n/ {
        rewrite ^/n8n/?(.*)$ /$1 break;
        proxy_pass http://n8n_service;
    }

    location /webui/ {
        rewrite ^/webui/?(.*)$ /$1 break;
        proxy_pass http://open_webui_service;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location /ollama/ {
        rewrite ^/ollama/?(.*)$ /$1 break;
        proxy_pass http://ollama_service;
    }

    location /llamacpp/ {
        rewrite ^/llamacpp/?(.*)$ /$1 break;
        proxy_pass http://llamacpp_service;
    }

    location /portainer/ {
        rewrite ^/portainer/?(.*)$ /$1 break;
        proxy_pass http://portainer_service;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

server {
    listen 80;
    server_name portainer.phoenix.local;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name portainer.phoenix.local;

    ssl_certificate /etc/nginx/ssl/portainer.phoenix.local.crt;
    ssl_certificate_key /etc/nginx/ssl/portainer.phoenix.local.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:ECDHE-RSA-AES128-GCM-SHA256';
    ssl_prefer_server_ciphers off;

    location / {
        proxy_pass https://portainer_service;
        proxy_ssl_verify off;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

EOF

# --- Service Management and Validation ---
echo "Testing Nginx configuration..."
nginx -t

echo "Enabling and restarting Nginx service..."
systemctl enable nginx
systemctl restart nginx

echo "Performing health check on Nginx service..."
if ! systemctl is-active --quiet nginx; then
    echo "Nginx service health check failed. The service is not running." >&2
    exit 1
fi

echo "Nginx API Gateway has been configured successfully in LXC 101."
exit 0