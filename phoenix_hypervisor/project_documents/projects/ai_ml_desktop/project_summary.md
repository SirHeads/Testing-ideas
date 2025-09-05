# Project Summary: AI/ML Desktop Environment

## Overview
This project aims to create a functional and efficient Linux desktop environment within an LXC container on a Proxmox 9 host. The environment will be optimized for AI/ML workloads, learning, and remote access. It will leverage two NVIDIA 5060 Ti 16GB GPUs for hardware acceleration and utilize lightweight desktop components to minimize overhead.

The primary goals are to achieve strong isolation, seamless GPU passthrough, high-performance remote desktop access via RustDesk, and a scalable architecture that allows for the creation of multiple, similar containerized environments. This initiative is based on successful implementations and best practices gathered from the Proxmox and homelab communities.