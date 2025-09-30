---
title: 'Feature: Ollama'
summary: The `ollama` feature automates the installation and configuration of the Ollama LLM serving platform, including setting up a robust systemd service to manage the process.
document_type: "Feature Summary"
status: "Approved"
version: "1.0.0"
author: "Phoenix Hypervisor Team"
owner: "Developer"
tags:
  - "Ollama"
  - "LLM Serving"
  - "AI"
  - "Systemd"
review_cadence: "Annual"
last_reviewed: "2025-09-30"
---

The `ollama` feature automates the installation and configuration of the Ollama LLM serving platform within an LXC container. It ensures that Ollama is set up as a reliable, auto-starting service, ready to serve models.

## Key Actions

1.  **Ollama Installation:** Downloads and executes the official Ollama installation script (`curl -fsSL https://ollama.com/install.sh | sh`), which places the `ollama` binary in the system's path.
2.  **Systemd Service Configuration:** Creates a custom systemd service file at `/etc/systemd/system/ollama.service`. This service is configured to:
    *   Start automatically on container boot.
    *   Restart automatically on failure.
    *   Listen on all network interfaces (`0.0.0.0:11434`), making the API accessible from outside the container.
3.  **Service Management:** Reloads the `systemd` daemon, enables the new `ollama` service, and starts it.
4.  **Verification:** Checks that the `ollama` service is active and that the API is responsive by making a `curl` request to the `/api/tags` endpoint.

## Idempotency

The script is idempotent. It first checks if the `ollama` command is already available in the container. If it is, the installation is skipped, and the script moves on to ensure the service is configured and running.

## Usage

This feature is applied to any container that will be used to host the Ollama service. For GPU-accelerated inference, it is essential that the `nvidia` feature is applied to the container before this one.