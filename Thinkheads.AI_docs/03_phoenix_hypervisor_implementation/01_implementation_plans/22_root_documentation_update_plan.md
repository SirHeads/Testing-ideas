---
title: "Plan to Update Root-Level Project Documentation"
summary: "This document outlines the plan to update the outdated README.md and HELP.md files in the root of the phoenix_hypervisor project to reflect the current dispatcher-manager architecture."
document_type: "Implementation Plan"
status: "Active"
version: "1.0.0"
author: "Roo"
owner: "Technical VP"
tags:
  - "Phoenix Hypervisor"
  - "Documentation"
  - "Refactoring"
review_cadence: "Ad-Hoc"
last_reviewed: "2025-09-30"
---

# Plan to Update Root-Level Project Documentation

## 1. Introduction

This document outlines the plan to update the `README.md` and `HELP.md` files located in the root of the `usr/local/phoenix_hypervisor/` directory. These files are critically outdated and still refer to the legacy `phoenix_orchestrator.sh` script, which has been deprecated and replaced by the new `phoenix` CLI and its dispatcher-manager architecture.

## 2. Scope of Work

The following files will be updated:

*   `usr/local/phoenix_hypervisor/README.md`
*   `usr/local/phoenix_hypervisor/HELP.md`

## 3. Required Changes

### 3.1. `README.md` Updates

The `README.md` will be rewritten to accurately reflect the current state of the project. The key changes will include:

*   **Update Core Architecture Section:** Replace references to `phoenix_orchestrator.sh` with the `phoenix` CLI.
*   **Update Installation Instructions:** Provide the correct, simplified installation and setup instructions using the new CLI.
*   **Update Usage Examples:** Replace all usage examples with the new verb-first command structure (e.g., `phoenix create 950`, `phoenix setup`).
*   **Remove Outdated Sections:** Remove any sections that are no longer relevant to the current architecture.

### 3.2. `HELP.md` Updates

The `HELP.md` file will be updated to serve as a concise and accurate quick-reference guide for the new `phoenix` CLI. The key changes will include:

*   **Update Overview:** Rewrite the overview to describe the dispatcher-manager architecture.
*   **Update Usage Section:** Replace the outdated command examples with a clear and comprehensive list of the new verbs and their usage.
*   **Consolidate Content:** Ensure that the content is focused and provides immediate value to a user seeking help with the CLI.

## 4. Implementation Plan

1.  **Draft New `README.md`:** Create a new version of the `README.md` that incorporates all the required changes.
2.  **Draft New `HELP.md`:** Create a new version of the `HELP.md` that is aligned with the new CLI.
3.  **Review and Approve:** Submit the new documentation for review and approval.
4.  **Replace Old Files:** Once approved, replace the outdated files in the `usr/local/phoenix_hypervisor/` directory.