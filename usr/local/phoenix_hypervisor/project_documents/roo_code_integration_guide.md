---
title: Roo Code Integration Guide
summary: This document provides the necessary configuration settings to integrate the Roo Code extension in VS Code with your self-hosted embedding model and Qdrant vector database.
document_type: Technical
status: Approved
version: 1.0.0
author: Phoenix Hypervisor Team
owner: Thinkheads.AI
tags:
- Roo Code
- VS Code
- Integration
- Embedding Model
- Qdrant
review_cadence: Annual
last_reviewed: 2025-09-23
---

# Roo Code Integration Guide

This document provides the necessary configuration settings to integrate the Roo Code extension in VS Code with your self-hosted embedding model and Qdrant vector database.

### Step-by-Step Configuration Guide

1.  **Open VSCode Settings:**
    *   On Windows/Linux, go to **File > Preferences > Settings**.
    *   On macOS, go to **Code > Settings > Settings**.
    *   Alternatively, use the shortcut `Ctrl+,` (or `Cmd+,` on macOS).

2.  **Navigate to RooCode Extension Settings:**
    *   In the Settings search bar, type `RooCode` to filter the settings.
    *   Click on **RooCode** under the **Extensions** section to view its configuration options.

3.  **Configure the Embedder Settings:**
    *   Find the **RooCode: Embedder** section.
    *   Set the **Api Base** to your embedding service URL.
    *   Leave the **Api Key** field **blank**.
    *   Set the **Model Dimension** to the correct value for your model.
    *   Set the **Model Name** to match your embedding model.

4.  **Configure the Vector Store (Qdrant) Settings:**
    *   Find the **RooCode: Vector Store** section.
    *   Leave the **Api Key** field **blank**.
    *   Set the **Url** to your Qdrant instance URL.

5.  **Save and Reload:**
    *   Your changes should save automatically.
    *   To ensure the new settings are applied, you can restart VSCode by closing and reopening it, or by running the `Developer: Reload Window` command from the Command Palette (`Ctrl+Shift+P` or `Cmd+Shift+P`).

### Configuration Settings Table

Here is a summary of the exact values you need to enter in the RooCode extension settings:

| Setting                  | Section             | Value                                           |
| :----------------------- | :------------------ | :---------------------------------------------- |
| **Api Base**             | `RooCode: Embedder` | `http://10.0.0.151:8000/v1`                     |
| **Api Key**              | `RooCode: Embedder` | *(Leave this field blank)*                      |
| **Model Dimension**      | `RooCode: Embedder` | `768`                                           |
| **Model Name**           | `RooCode: Embedder` | `ibm-granite/granite-embedding-english-r2`      |
| **Api Key**              | `RooCode: Vector Store` | *(Leave this field blank)*                      |
| **Url**                  | `RooCode: Vector Store` | `http://10.0.0.152:6334`                        |

## Architecture Diagram

The following diagram illustrates the architecture of the integration:

```mermaid
graph TD
    subgraph VS Code
        A[Roo Code Extension]
    end

    subgraph "Phoenix Hypervisor"
        B[Embedding Model <br> CTID 951 <br> 10.0.0.151:8000]
        C[Qdrant <br> CTID 953 <br> 10.0.0.152:6334]
    end

    A -- "Embeddings API Request" --> B
    A -- "Vector Search/Storage" --> C
```

## Advanced Configuration

Based on your initial request, here are some suggested values for the advanced configuration:

*   **Search Score Threshold:** `0.40`
*   **Maximum Search Results:** `50`

These values can be adjusted based on your specific needs and the performance of the system.