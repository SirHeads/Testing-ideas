# Nginx Configuration Update Proposal

## 1. Problem

The current Nginx configuration generation script (`generate_nginx_gateway_config.sh`) creates an incomplete `location` block for the ACME challenge, causing the Step CA validation to fail.

## 2. Proposed Solution

I propose to update the `generate_nginx_gateway_config.sh` script to include the necessary `proxy_set_header` directives in the `location /.well-known/acme-challenge/` block.

### `generate_nginx_gateway_config.sh`

```diff
--- a/usr/local/phoenix_hypervisor/bin/generate_nginx_gateway_config.sh
+++ b/usr/local/phoenix_hypervisor/bin/generate_nginx_gateway_config.sh
@@ -45,8 +45,11 @@
 
     # Proxy ACME challenges to Traefik's http-01 challenge solver
     location /.well-known/acme-challenge/ {
-        proxy_pass http://10.0.0.12:80;
-        proxy_set_header Host \$host;
+        proxy_pass http://10.0.0.12:80; # Forward to Traefik's HTTP entrypoint
+        proxy_set_header Host \$host;
+        proxy_set_header X-Real-IP \$remote_addr;
+        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
+        proxy_set_header X-Forwarded-Proto \$scheme;
     }
 
     # Redirect all other traffic to the HTTPS equivalent

```

This change will ensure that the ACME challenge requests are correctly proxied to Traefik with all the necessary information.