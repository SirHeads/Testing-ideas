---
title: "REST API Reference"
summary: "This document provides a reference for the Phoenix Hypervisor REST API."
document_type: "API Reference"
status: "Draft"
version: "1.0.0"
author: "Thinkheads.AI"
owner: "Developer"
tags:
  - "API"
  - "REST"
  - "Reference"
review_cadence: "Annual"
last_reviewed: "2025-09-29"
---

# REST API Reference

This document provides a reference for the Phoenix Hypervisor REST API.

## 1. Overview

The Phoenix Hypervisor API provides a set of endpoints for managing containers, VMs, and services. The API is organized around REST principles and uses standard HTTP response codes to indicate API errors.

## 2. Authentication and Authorization

All API requests must be authenticated using an API key. The API key must be included in the `Authorization` header of each request.

```
Authorization: Bearer <YOUR_API_KEY>
```

## 3. Endpoints

### Containers

*   **GET /containers** - Get a list of all containers.
*   **GET /containers/{id}** - Get a specific container.
*   **POST /containers** - Create a new container.
*   **PUT /containers/{id}** - Update a container.
*   **DELETE /containers/{id}** - Delete a container.

### Virtual Machines

*   **GET /vms** - Get a list of all VMs.
*   **GET /vms/{id}** - Get a specific VM.
*   **POST /vms** - Create a new VM.
*   **PUT /vms/{id}** - Update a VM.
*   **DELETE /vms/{id}** - Delete a VM.

### Services

*   **GET /services** - Get a list of all services.
*   **GET /services/{id}** - Get a specific service.
*   **POST /services** - Create a new service.
*   **PUT /services/{id}** - Update a service.
*   **DELETE /services/{id}** - Delete a service.

## 4. Example Requests and Responses

### Get a list of all containers

**Request:**

```bash
curl -X GET \
  http://phoenix-hypervisor.local/api/v1/containers \
  -H 'Authorization: Bearer <YOUR_API_KEY>'
```

**Response:**

```json
[
  {
    "id": 950,
    "name": "vllm-qwen2.5-7b-awq",
    "status": "running"
  },
  {
    "id": 951,
    "name": "vllm-granite-embed-r2",
    "status": "running"
  }
]