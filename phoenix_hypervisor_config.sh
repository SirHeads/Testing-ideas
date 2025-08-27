#!/bin/bash
# Configuration file for Phoenix Hypervisor
# Defines essential file paths and default settings for LXC creation on Proxmox
# Version: 0.01.01 (Initial framing of configurations)
# Author: Heads, Qwen3-coder

# --- Core Paths ---
# Path to the main LXC configuration JSON file
# Note: Contains per-container settings (e.g., memory, GPU, Portainer role). Must exist and be valid JSON.
export PHOENIX_LXC_CONFIG_FILE="${PHOENIX_LXC_CONFIG_FILE:-/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.json}"

# Path to the JSON schema for validating the LXC configuration
# Note: Used to ensure config JSON adheres to schema. Must exist and be valid JSON schema.
export PHOENIX_LXC_CONFIG_SCHEMA_FILE="${PHOENIX_LXC_CONFIG_SCHEMA_FILE:-/usr/local/phoenix_hypervisor/etc/phoenix_lxc_configs.schema.json}"

# Path to the Hugging Face token file
# Note: Contains API token for downloading AI models (e.g., Qwen2.5-Coder-7B). Must be readable and secure (chmod 600 or 640).
export PHOENIX_HF_TOKEN_FILE="${PHOENIX_HF_TOKEN_FILE:-/usr/local/phoenix_hypervissor/etc/phoenix_hf_token.conf}"

# Path to the Docker Hub token file
# Note: Contains credentials for Docker Hub image pulls (e.g., Portainer images). Must be readable and secure (chmod 600 or 640).
export PHOENIX_DOCKER_TOKEN_FILE="${PHOENIX_DOCKER_TOKEN_FILE:-/usr/local/phoenix_hypervisor/etc/phoenix_docker_token.conf}"

# Path to the shared directory containing Docker images/contexts (e.g., Modelfiles)
# Note: Should be accessible from the Proxmox host and mounted appropriately.
export PHOENIX_DOCKER_IMAGES_PATH="${PHOENIX_DOCKER_IMAGES_PATH:-/usr/local/phoenix_hypervisor/etc/proxmox_docker_images}"

# Directory for Phoenix Hypervisor marker files
# Used to track setup status and potentially other states.
export HYPERVISOR_MARKER_DIR="${HYPERVISOR_MARKER_DIR:-/usr/local/phoenix_hypervisor/lib}"
export HYPERVISOR_MARKER="${HYPERVISOR_MARKER:-$HYPERVISOR_MARKER_DIR/.phoenix_hypervisor_initialized}"

# URL for the external Docker registry (Docker Hub with username SirHeads)
# Note: Used for authenticated pulls/pushes, critical for Portainer (container 999) to manage Docker images.
export EXTERNAL_REGISTRY_URL="${EXTERNAL_REGISTRY_URL:-docker.io/SirHeads}"

# ZFS pool for LXC container storage
# Note: Must be an existing ZFS pool with sufficient space for AI workloads (e.g., 64-216 GB per container).
export PHOENIX_ZFS_LXC_POOL="${PHOENIX_ZFS_LXC_POOL:-quickOS/lxc-disks}"

# Default CPU cores for LXC containers
# Note: For AI workloads, 2-8 cores recommended; overridden by JSON config for specific containers.
export DEFAULT_LXC_CORES="${DEFAULT_LXC_CORES:-2}"

# Default memory (RAM) in MB for LXC containers
# Note: For AI workloads, 2048-32768 MB recommended; JSON config overrides for larger models (e.g., 32-90 GB).
export DEFAULT_LXC_MEMORY_MB="${DEFAULT_LXC_MEMORY_MB:-2048}"

# Default network configuration (CIDR, Gateway, DNS)
# Note: Format compatible with Proxmox 'pct' commands. JSON config provides per-container overrides.
export DEFAULT_LXC_NETWORK_CONFIG="${DEFAULT_LXC_NETWORK_CONFIG:-10.0.0.110/24,10.0.0.1,8.8.8.8}"

# Default LXC features (e.g., nesting=1,keyctl=1)
# Note: Nesting required for Docker-in-LXC (e.g., Portainer); keyctl optional for advanced capabilities.
export DEFAULT_LXC_FEATURES="${DEFAULT_LXC_FEATURES:-nesting=1}"

# IP address of the Portainer Server container
# Note: Must match container 999's IP (Portainer server) in JSON config for agent connections.
export PORTAINER_SERVER_IP="${PORTAINER_SERVER_IP:-10.0.0.99}"

# Port for accessing the Portainer web UI
# Note: Port 9443 recommended for secure HTTPS access to Portainer UI (https://10.0.0.99:9443).
export PORTAINER_SERVER_PORT="${PORTAINER_SERVER_PORT:-9443}"

# Port for Portainer Agent communication
# Note: Must be accessible from other containers (e.g., 900, 901, 902) for cluster management.
export PORTAINER_AGENT_PORT="${PORTAINER_AGENT_PORT:-9001}"

# Rollback on failure flag
# Note: If 'true', scripts attempt to rollback failed LXC creations (e.g., delete partial containers).
export ROLLBACK_ON_FAILURE="${ROLLBACK_ON_FAILURE:-false}"

# Note: 'unconfined' allows GPU/Docker access but reduces security; 'default' recommended for production.
# Warning: Conflicts with JSON 'unprivileged'; ensure alignment in scripts.
export DEFAULT_CONTAINER_SECURITY="${DEFAULT_CONTAINER_SECURITY:-default}"

# Note: Required for Docker-in-LXC (e.g., Portainer, optional AI containers). Redundant with DEFAULT_LXC_FEATURES.
export DEFAULT_CONTAINER_NESTING="${DEFAULT_CONTAINER_NESTING:-1}"

# Note: If 'true', skips validation and logs detailed output for troubleshooting.
export DEBUG_MODE="${DEBUG_MODE:-false}"

# Signal that this configuration file has been loaded
export PHOENIX_HYPERVISOR_CONFIG_LOADED=1
