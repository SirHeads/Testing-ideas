# Documentation Restructure Proposal v2

## 1. Introduction

This document outlines a revised, comprehensive proposal for restructuring the project documentation. The feedback on the initial proposal has made it clear that the goal is not to simplify by exclusion, but to create a rich, multi-layered, and highly organized knowledge base.

This new structure is designed to serve a wide range of personas—from executive leadership to marketing, product, technical leaders, developers, and end-users. The ultimate objective is to build a knowledge base that can be queried by a sophisticated LLM, capable of providing answers ranging from high-level strategic vision to granular implementation details.

## 2. Guiding Principles

The proposed structure is based on the following principles:

*   **Persona-Driven:** The hierarchy is organized around the likely consumers of the information, from corporate strategy to technical implementation.
*   **Hierarchical and Logical:** The structure flows from the general to the specific, allowing for easy navigation and contextual understanding.
*   **Comprehensive:** Every existing document is given a logical home. No information is discarded.
*   **Optimized for RAG:** The clear structure and categorization will provide strong metadata for a Retrieval-Augmented Generation system, improving the accuracy and relevance of LLM-driven queries.
*   **Scalable:** The structure is designed to accommodate future projects and documentation without requiring another major overhaul.

## 3. Proposed New Folder Structure

The new documentation will be consolidated under a single `docs/` directory, with a clear, persona-driven top-level hierarchy.

```
docs/
├── 00_corporate_strategy/
├── 01_product_and_project_strategy/
├── 02_technical_strategy_and_architecture/
└── 03_phoenix_hypervisor_implementation/
```

## 4. Detailed File Mapping

This section provides a detailed breakdown of the new structure and maps every existing document to its new location.

### `docs/00_corporate_strategy/`

*   **Target Audience:** CEO, VPs, Executive Leadership
*   **Content:** High-level vision, mission, business strategy, and operational principles.

```
docs/00_corporate_strategy/
├── 00_vision_and_mission/
│   ├── 00_vision_statement.md
│   ├── 01_mission_statement.md
│   └── 02_core_values.md
├── 01_business_strategy/
│   ├── 00_v2mom.md
│   ├── 01_swot_analysis.md
│   ├── 02_competitive_landscape.md
│   └── 03_business_model_canvas.md
└── 02_operations/
    ├── 00_organizational_structure.md
    ├── 01_kpis_and_metrics.md
    └── 02_budget_and_financials.md
```

### `docs/01_product_and_project_strategy/`

*   **Target Audience:** Product VPs, Project Managers, Marketing
*   **Content:** Product roadmaps, market analysis, user personas, and detailed business cases for each project.

```
docs/01_product_and_project_strategy/
├── 00_product_strategy/
│   ├── 00_product_roadmap.md
│   ├── 01_market_analysis.md
│   └── 02_user_personas.md
└── 01_project_business_cases/
    ├── 00_learning_assistant_business_case.md
    ├── 01_meeting_room_business_case.md
    ├── 02_online_card_game_business_case.md
    ├── 03_thinkheads_website_business_case.md
    └── 04_user_profiles_business_case.md
```

### `docs/02_technical_strategy_and_architecture/`

*   **Target Audience:** Technical VP, Architects, Tech Leads
*   **Content:** High-level technical vision, architectural principles, and system-wide strategy documents.

```
docs/02_technical_strategy_and_architecture/
├── 00_technical_vision.md
├── 01_architectural_principles.md
├── 02_technology_stack.md
├── 03_phoenix_hypervisor_strategy.md
├── 04_phoenix_hypervisor_technical_strategy.md
└── 05_rag_optimization_strategy.md
```

### `docs/03_phoenix_hypervisor_implementation/`

*   **Target Audience:** Developers, DevOps, Technical Support
*   **Content:** Detailed guides, implementation plans, remediation procedures, and technical references for the Phoenix Hypervisor project.

```
docs/03_phoenix_hypervisor_implementation/
├── 00_guides/
│   ├── 00_system_architecture_guide.md
│   ├── 01_declarative_architecture_guide.md
│   ├── 02_lxc_container_implementation_guide.md
│   ├── 03_nvidia_gpu_management_guide.md
│   ├── 04_roo_code_integration_guide.md
│   ├── 05_vllm_integration_testing_guide.md
│   └── 06_troubleshooting_guide.md
├── 01_implementation_plans/
│   ├── 00_unified_phoenix_hypervisor_strategy_v2.md
│   ├── 01_implementation_plan.md
│   ├── 02_lxc_951_refactored_plan.md
│   ├── 03_lxc_955_ollama_integration_plan.md
│   ├── 04_snapshot_and_boot_order_enhancements.md
│   └── 05_zfs_datasets_plan.md
├── 02_remediation_plans/
│   ├── 00_systemic_remediation_plan.md
│   ├── 01_pct_exec_remediation_plan.md
│   ├── 02_unhealthy_container_remediation_plan.md
│   └── 03_vllm_systemd_fix_plan.md
├── 03_quality_and_testing/
│   ├── 00_phoenix_hypervisor_qa_plan.md
│   ├── 01_verification_plan.md
│   └── 02_testing.md
├── 04_feature_summaries/
│   ├── 00_feature_base_setup_summary.md
│   ├── 01_feature_docker_summary.md
│   └── 02_feature_vllm_summary.md
└── 05_archive_and_legacy/
    ├── 00_phoenix_hypervisor_final_summary.md
    ├── 01_future_enhancements_and_vision.md
    ├── 02_unhealthy_container_report.md
    └── ... (other historical documents)
```

## 5. Identified Gaps and Recommendations

After organizing the existing documentation, several gaps become apparent. I recommend creating the following new documents to create a more complete and user-friendly knowledge base:

1.  **`docs/03_phoenix_hypervisor_implementation/00_guides/00_getting_started.md`**: A crucial document for new developers, outlining how to set up their environment, clone the repository, and run the orchestrator for the first time.
2.  **`docs/01_product_and_project_strategy/00_product_strategy/03_marketing_overview.md`**: A document aimed at the marketing team, providing a high-level overview of the products, their key features, and target audiences.
3.  **`docs/02_technical_strategy_and_architecture/06_system_diagrams.md`**: A centralized document containing Mermaid diagrams of the high-level system architecture, network topology, and data flow. This will be invaluable for all technical personas.
4.  **User Manuals for each sub-product**: For example, `docs/01_product_and_project_strategy/01_project_business_cases/00_learning_assistant_user_manual.md`. These would be aimed at end-users, explaining how to use the features of each application.

## 6. Proposed Revisions and Merges

I also recommend the following revisions to existing documents:

1.  **Merge `ROOCODE_VLLM_INTEGRATION.md` and `vscode_lxc_roocode_integration.md`**: These two documents cover very similar topics and should be merged into the `roo_code_integration_guide.md` to create a single, authoritative source.
2.  **Expand `troubleshooting_guide.md`**: This guide is a good start, but it should be expanded with more common issues and their resolutions as they are discovered. It should become a living document.
3.  **Standardize all documents with YAML front-matter**: To improve RAG performance, every single markdown file should have a standardized YAML front-matter block with fields like `title`, `summary`, `document_type`, `status`, `version`, `author`, `owner`, `tags`, `review_cadence`, and `last_reviewed`.

## 7. Next Steps

This proposal represents a significant step towards building a world-class documentation system. I recommend the following next steps:

1.  **Review and Approve:** Please review this proposal and provide feedback. I am ready to make any necessary adjustments.
2.  **Switch to Code Mode:** Once the plan is approved, I will request to switch to **Code Mode** to execute the file and directory operations required to implement this new structure.

I am confident that this new structure will meet the project's ambitious goals and provide a solid foundation for the future.