# LXC Template Dependency Flow

This diagram illustrates the correct, non-circular workflow for creating LXC containers from a base OS template and then generating specialized templates from those base containers.

```mermaid
graph TD
    subgraph "Phase 1: Base Container Creation"
        A[OS Template e.g., ubuntu-24.04.tar.zst] -->|Used to create| B(CT 900 'Copy-Base');
    end

    subgraph "Phase 2: Template Generation"
        B -->|Used to generate| C[LXC Template 'copy-base-v1.tar.gz'];
    end

    subgraph "Phase 3: Specialized Container Creation"
        B -->|Cloned to create| D(CT 901 'Copy-Cuda12.8');
        C -->|Used to create| E[Other Containers];
    end

    style A fill:#d4fcd7,stroke:#333,stroke-width:2px
    style C fill:#d4fcd7,stroke:#333,stroke-width:2px
    style B fill:#f9f7d9,stroke:#333,stroke-width:2px
    style D fill:#f9f7d9,stroke:#333,stroke-width:2px
    style E fill:#f9f7d9,stroke:#333,stroke-width:2px
```

## Explanation

1.  **Base Container Creation:** The process must start with a downloaded OS template (e.g., Ubuntu 24.04). This is used to create the initial, foundational container, `CT 900`.
2.  **Template Generation:** Once `CT 900` is fully configured with base setup, it is used to generate a reusable LXC template (`copy-base-v1.tar.gz`).
3.  **Specialized Container Creation:** Subsequent containers that require the same base configuration can then be efficiently created by either:
    *   **Cloning** directly from the now-existing `CT 900`.
    *   **Creating from the template** file `copy-base-v1.tar.gz`.

The error we are seeing is because the logic attempts to use the `copy-base-v1.tar.gz` template to create `CT 900`, which is a circular dependency. The proposed code change ensures that for `CT 900`, the script uses the OS Template directly.