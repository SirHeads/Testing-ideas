# Phoenix Hypervisor

This repository contains the scripts and configuration files for the Phoenix Hypervisor project.

## Installation

These instructions will guide you through the process of downloading and extracting the necessary files for the Phoenix Hypervisor on a new Proxmox installation.

### 1. Download the release

Log in to your Proxmox host as the `root` user and download the latest release from the GitHub repository.

```bash
wget https://github.com/SirHeads/Testing-ideas/archive/refs/tags/v01.05.01.tar.gz -O Testing-ideas-v01.05.01.tar.gz
```

### 2. Extract the archive

Extract the contents of the downloaded tar.gz file.

```bash
tar -xzvf Testing-ideas-v01.05.01.tar.gz
```

### 3. Move the `phoenix_hypervisor` directory

This will move the `phoenix_hypervisor` directory from the extracted folder to `/usr/local/`.

```bash
mv Testing-ideas-01.05.01/usr/local/phoenix_hypervisor /usr/local/
```

### 4. Set permissions

Make the main orchestrator script executable. You may need to adjust permissions for other scripts as needed.

```bash
chmod +x /usr/local/phoenix_hypervisor/bin/phoenix_orchestrator.sh
```

### 5. Clean up

Remove the downloaded archive and the extracted folder.

```bash
rm Testing-ideas-v01.05.01.tar.gz
rm -rf Testing-ideas-01.05.01
```

## About the Project

The Phoenix Hypervisor is a collection of scripts designed to automate the setup and management of LXC containers and VMs on a Proxmox host. It provides a declarative way to manage your infrastructure, making it easy to reproduce and maintain your environment.

### Key Features

*   **Declarative Configuration:** Define your containers and VMs in JSON configuration files.
*   **Automated Setup:** Scripts to automate the installation and configuration of various services like Docker, NVIDIA drivers, Ollama, and more.
*   **Modular Design:** The scripts are organized into modules for different functionalities, making it easy to extend and customize.
*   **Health Checks:** Includes scripts to monitor the health of your containers and services.

## Getting Started

Once you have completed the installation steps, you can start using the `phoenix_orchestrator.sh` script to manage your environment.

For more information on how to use the scripts and configure your environment, please refer to the documentation in the `Thinkheads.AI_docs` directory.