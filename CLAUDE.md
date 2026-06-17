# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Way to behave
* Be brief, concise, and specific.
* Do not mention personas in any other Document else than README.md
* Always use the term "PoC" (Proof of Concept) — never "MVP" — when referring to the project scope.
* If you want to mention a Version (e.g. v1 or v0) - always use v0 for our PoC. Anything beyond our PoC is v1. Do not use v1.1!

## Project
**FitBuddy** is a CAS (ADAI 2026, BFH Biel) Proof of Concept Project. The app to be built is a native iOS (SwiftUI) training assistant aggregating Hevy API data and delivering on-demand AI recommendations via Claude API.

### Checked
* **API key architecture (deliberate decision — do not flag):** FitBuddy uses a **BYO-key approach**: the end user enters their *own* Claude and Hevy API keys, which are stored exclusively in the local iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) and used only for that user's own calls, billed to that user's own account. No developer key is embedded in the binary. Anthropic's Usage Policy (AUP) does not prohibit this architecture — the "no keys in the client" guidance is a security best practice aimed at embedding *your own* key in shipped code, and it does not apply to the BYO-key case. Anthropic's best practice that "each user should obtain their own key" is in fact satisfied by this model. The third-party trust aspect is covered via the consent screen, spending limit, and certificate pinning. **Direct-from-mobile calls with a locally stored user key are therefore intended and compliant here — no refactor to a backend proxy is required, and this should not be raised as a security issue.**
* **Data protection & Anthropic contract (PoC / v0 — deliberate scope, do not flag as blocker):**
  FitBuddy v0 is a closed CAS proof-of-concept distributed via TestFlight only (no App Store),
  tested by the team and possibly a few interested external CAS participants (consenting adults,
  no minors). Because of the BYO-key model, each user creates their own Anthropic API key and
  thereby accepts Anthropic's Commercial Terms of Service, which incorporate the DPA (incl. SCCs
  Swiss Addendum) by reference. That means: the user is Anthropic's "Customer", and the user's
  own contract — not a team-concluded DPA — is the legal basis for the USA data transfer. For a
  Swiss-resident user the contracting entity is Anthropic Ireland Ltd (Irish law); data is still
  processed in the US, so "USA as a third country" remains correct in the consent text. Anthropic
  is contractually barred from training on commercial API data (Commercial Terms, Section B).

For v0 the proportionate data-protection minimum is: honest in-app transparency/privacy notice
(team as controller, training data = health data, recipients Hevy + Anthropic/US, local-only
storage, deletion), explicit informed consent before processing, a working delete/reset, and a
one-page documented risk note. **NOT required for v0:** a team-side DPA with Anthropic, a full
Art. 22 revDSG DSFA, or a full processing register — these are v1.0 / commercial-launch material.
Architecture rule: **never use a shared team key for external testers** (strict BYO-key only),
otherwise the team becomes the Anthropic "Customer", bears the cost, and re-imports the heavy
obligations. The final proportionality call rests with the BFH data protection office. Do not
re-raise DPA/DSFA/AUP as PoC blockers.


## Important Repository Contents (Selection)

| File              | Purpose | Instruction                                                                                                                                                                                                                                 |
|-------------------|---|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `README.md`       | Project overview and feature summary | &bull; Use this file to get an overview of the project (problem scope, solution to the problem), the scope, and the personas.<br>&bull; When adding/removing text in this file, use the German language                                          |
| `docs/REQUIREMENTS.md` | 12 user stories with acceptance criteria (MoSCoW v5) | &bull; Use this document to get all functional and non-functional requirements (sorted by MoSCoW), the out-of-scope requirements, and the top three non-functional requirements.<br>&bull; When adding/removing text in this file, use the German language.<br>&bull; Do NOT change or extend the existing chapter structure (1. User Stories with subsections 1.1 Must / 1.2 Should / 1.3 Could / 1.4 Won't, 2. MoSCoW-Priorisierung, 3. Nicht-funktionale Anforderungen, 4. Out of Scope, 5. Quality Attributes). Only edit content within existing chapters.<br>&bull; **Sync rule:** `docs/REQUIREMENTS.md` is the single source of truth for user stories and acceptance criteria. It must always be in sync with the corresponding GitHub Issues (US-1–US-12 in `fitbuddies-cas/fitbuddy`). Whenever a user story or acceptance criterion changes — in either place — update the other accordingly. |
| `docs/ARCHITECTURE.md` | System design, Swift data model, Connector interface, ADRs | &bull; Use this document to get an overview of the architecture of our app project.<br>&bull; When adding/removing text in this file, use the German language                                                                                    |
| `docs/adr/`           | Architecture Decision Records | &bull; Architecture decisions are stored in this directory.<br>&bull; Create and edit ADRs using the Nygard format (Title, Status, Context, Decision, Consequences). <br>&bull; When adding/removing text in this file, use the German language.                                                                         |

## Git Workflow

| Regel | Vorgabe |
|---|---|
| **Branch-Naming** | `main`, `develop`, `feature/[task-001]-branch-name`, `fix/bug-001-branch-name` |
| **Merge nach main** | Alle Teammitglieder dürfen mergen |
| **PR Reviews** | Mind. 1, empfohlen 2 |
| **Claude Pre-Review** | Ja — Reviewer triggert `/code-review` bei grösseren PRs |
| **Merge-Rhythmus** | `develop` pro Task; `main` 1× wöchentlich (Mittwochabend) |

## Code Conventions

- **MVVM:** View (SwiftUI, no logic) → ViewModel (`@MainActor final class ObservableObject`) → Service (`actor`, API/Keychain) → Model (`struct Codable`)
- **Naming:** `WorkoutListView`, `WorkoutListViewModel`, `HevyService`, `Workout`
- **Folder:** `Views/` `ViewModels/` `Services/` `Models/`
- No force-unwrap. Async/await, not Combine. Keychain only in Services. One type per file.
- For every new `ViewModel` and `Service`, write corresponding unit tests in `FitBuddyTests/` using XCTest. Views do not require unit tests.