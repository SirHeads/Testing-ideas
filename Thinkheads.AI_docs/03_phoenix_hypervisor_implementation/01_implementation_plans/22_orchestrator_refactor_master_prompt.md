---
title: Master Prompt for Phoenix Orchestrator Refactor Project Planning
summary: A comprehensive prompt to be used by an AI project management agent to generate a detailed Work Breakdown Structure (WBS), Epics, and User Stories for the orchestrator refactoring project.
document_type: Prompt Template
status: Final
version: 1.0.0
author: Roo
owner: Technical VP
tags:
  - Phoenix Hypervisor
  - Orchestration
  - Refactoring
  - Project Management
  - Prompt Engineering
review_cadence: Ad-Hoc
last_reviewed: 2025-09-30
---

# Master Prompt: Phoenix Orchestrator Refactor Project Plan Generation

## 1. Role and Goal

You are an expert AI Project Manager. Your goal is to create a comprehensive and actionable project plan for the **Phoenix Orchestrator Refactoring** initiative. This plan must be detailed enough for a development team to begin work and for a project manager to track progress effectively.

## 2. Source Material

You must base your plan on the following key documents, which provide the strategic, architectural, and technical context for this project:

*   **Primary Technical Proposal:** `Thinkheads.AI_docs/02_technical_strategy_and_architecture/24_unified_cli_refactor_proposal.md`
*   **Supporting Technical Proposal:** `Thinkheads.AI_docs/02_technical_strategy_and_architecture/23_shell_orchestrator_refactor_proposal.md`
*   **Project Charter:** `Thinkheads.AI_docs/02_technical_strategy_and_architecture/25_orchestrator_refactor_project_charter.md`
*   **High-Level Implementation Plan:** `Thinkheads.AI_docs/03_phoenix_hypervisor_implementation/01_implementation_plans/21_orchestrator_refactor_implementation_plan.md`

## 3. Deliverable

You will produce a single markdown document titled **`26_orchestrator_refactor_wbs_and_epics.md`**. This document will contain the following sections:

### 3.1. Work Breakdown Structure (WBS)

*   A hierarchical breakdown of all the deliverables for this project.
*   The WBS should be detailed enough to capture all the major components of the project, including development, testing, documentation, and project management.
*   Use a nested list format for the WBS.

### 3.2. Epics and User Stories

*   A set of Epics that correspond to the four phases outlined in the **Project Charter** and **Implementation Plan**.
*   For each Epic, provide a set of detailed User Stories that are actionable and testable.
*   Each User Story should follow the standard format: "As a [user type], I want to [action] so that [benefit]."
*   Include acceptance criteria for each User Story.

## 4. Key Requirements and Constraints

*   **Phased Approach:** The plan must adhere to the four-phased approach outlined in the source documents.
*   **Technology Stack:** The implementation will be done exclusively in shell script. No other programming languages are to be introduced.
*   **Testing:** Each phase must include comprehensive testing, including unit, integration, and end-to-end tests.
*   **Documentation:** The plan must include tasks for updating all relevant user and developer documentation.
*   **Idempotency and Error Handling:** The implementation must be idempotent and include robust error handling, as specified in the implementation plan.

## 5. Example Structure

Here is a sample structure for the **Epics and User Stories** section to guide your output:

---

### Epic 1: Smart Dispatcher and Hypervisor Logic

*   **Description:** Establish the new `phoenix` CLI and migrate the hypervisor setup functionality.

#### User Stories

*   **Story 1.1:** As a developer, I want a `phoenix` script that can parse verb-first commands so that I can easily invoke the orchestrator's functionality.
    *   **Acceptance Criteria:**
        *   The `phoenix` script exists in the `bin/` directory.
        *   The script can correctly parse commands like `phoenix setup`, `phoenix create`, etc.
        *   The script provides a helpful error message for invalid commands.

*   **Story 1.2:** As a system administrator, I want to run `phoenix setup` to configure the hypervisor so that I can easily initialize a new host.
    *   **Acceptance Criteria:**
        *   The `phoenix setup` command correctly invokes the `hypervisor-manager.sh` script.
        *   The hypervisor setup process completes successfully and idempotently.
        *   All hypervisor-related logic is contained within `hypervisor-manager.sh`.

---

## 6. Final Instruction

Generate the complete `26_orchestrator_refactor_wbs_and_epics.md` document based on the provided source material and instructions. Ensure that the output is well-structured, detailed, and ready to be used by the project team.