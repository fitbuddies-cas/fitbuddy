# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Way to behave
* Be brief, concise, and specific.
* Do not mention personas in any other Document else than README.md

## Project
**FitBuddy** is a CAS (ADAI 2026, BFH Biel) Proof of Concept Project. The app to be built is a native iOS (SwiftUI) training assistant aggregating Hevy API data and delivering on-demand AI recommendations via Claude API.

## Important Repository Contents (Selection)

| File              | Purpose | Instruction                                                                                                                                                                                                                                 |
|-------------------|---|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `README.md`       | Project overview and feature summary | &bull; Use this file to get an overview of the project (problem scope, solution to the problem), the scope, and the personas.<br>&bull; When adding/removing text in this file, use the German language                                          |
| `REQUIREMENTS.md` | 12 user stories with acceptance criteria (MoSCoW v5) | &bull; Use this document to get all functional and non-functional requirements (sorted by MoSCoW), the out-of-scope requirements, and the top three non-functional requirements.<br>&bull; When adding/removing text in this file, use the German language.<br>&bull; Do NOT change or extend the existing chapter structure (1. User Stories with subsections 1.1 Must / 1.2 Should / 1.3 Could / 1.4 Won't, 2. MoSCoW-Priorisierung, 3. Nicht-funktionale Anforderungen, 4. Out of Scope, 5. Quality Attributes). Only edit content within existing chapters. |
| `ARCHITECTURE.md` | System design, Swift data model, Connector interface, ADRs | &bull; Use this document to get an overview of the architecture of our app project.<br>&bull; When adding/removing text in this file, use the German language                                                                                    |
| `ADRs/`           | Architecture Decision Records | &bull; Architecture decisions are stored in this directory.<br>&bull; Create and edit ADRs using the Nygard format (Title, Status, Context, Decision, Consequences). <br>&bull; When adding/removing text in this file, use the German language.                                                                         |

## Code Conventions
- To be defined (MVVM etc.)