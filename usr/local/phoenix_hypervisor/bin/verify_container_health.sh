#!/bin/bash

# Check vLLM container (951) health
if curl -s http://localhost:8000/health | grep -q '{"status":"ok"}'; then
  echo "Container 951 (vllm-granite-embed): Healthy"
else
  echo "Container 951 (vllm-granite-embed): Unhealthy"
fi

# Check Qdrant container (952) health
if curl -s http://localhost:6333/health | grep -q "ok"; then
  echo "Container 952 (qdrant-lxc): Healthy"
else
  echo "Container 952 (qdrant-lxc): Unhealthy"
fi

# Check API Gateway container (953) health
if systemctl is-active nginx >/dev/null; then
  echo "Container 953 (api-gateway-lxc): Healthy"
else
  echo "Container 953 (api-gateway-lxc): Unhealthy"
fi