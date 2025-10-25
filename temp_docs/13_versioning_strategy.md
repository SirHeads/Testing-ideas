---
title: "Documentation Versioning Strategy"
summary: "This document outlines the versioning strategy for the Phoenix Hypervisor documentation."
document_type: "Implementation Guide"
status: "Published"
version: "1.0.0"
author: "Thinkheads.AI"
owner: "Developer"
tags:
  - "Versioning"
  - "Documentation"
review_cadence: "Annual"
last_reviewed: "2025-09-29"
---

# Documentation Versioning Strategy

This document outlines the versioning strategy for the Phoenix Hypervisor documentation.

## 1. Versioning Scheme

The documentation will follow the same versioning scheme as the Phoenix Hypervisor project, which is based on Semantic Versioning (SemVer). The version number is composed of three parts: MAJOR.MINOR.PATCH.

*   **MAJOR** version when you make incompatible API changes.
*   **MINOR** version when you add functionality in a backwards-compatible manner.
*   **PATCH** version when you make backwards-compatible bug fixes.

## 2. Versioning in Documents

Each document will include a `version` field in its frontmatter. This field will be updated to reflect the version of the Phoenix Hypervisor that the document corresponds to.

## 3. Accessing Different Versions

To access documentation for a specific version of the Phoenix Hypervisor, users can check out the corresponding tag in the Git repository. For example, to access the documentation for version 2.1.0, you would run the following command:

```bash
git checkout v2.1.0