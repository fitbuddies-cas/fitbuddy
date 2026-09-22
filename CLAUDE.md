# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Way to behave
* Be brief, concise, and specific.
* Do not mention personas in any other Document else than README.md
* Always use the term "PoC" (Proof of Concept) — never "MVP" — when referring to the project scope.
* If you want to mention a Version (e.g. v1 or v0) - always use v0 for our PoC. Anything beyond our PoC is v1. Do not use v1.1!

## Language Policy

FitBuddy is bilingual by design — English and German each have a fixed scope, never interchangeable:

| Artifact | Language |
|---|---|
| Swift code — identifiers, comments | English |
| In-app UI text | English |
| Branch & file names | English |
| Commit messages | English |
| `README.md`, `docs/*.md`, `docs/adr/` | German |
| GitHub Issues (titles & bodies) | German |
| PR titles & descriptions, PR / code reviews (`/code-review`, `/pr-review`) | German — the verdict label (`approve` / `approve-after-fixes` / `request changes`) stays the fixed English tag |

Rule of thumb: code and what sits directly on top of it (comments, commits) is English; anything the team reads as documentation, planning, or review discussion (docs, issues, PRs, reviews) is German.

## Project
**FitBuddy** is a CAS (ADAI 2026, BFH Biel) Proof of Concept Project. The app to be built is a native iOS (SwiftUI) training assistant aggregating Hevy API data and delivering on-demand AI recommendations via Claude API.

### Checked
* **API key architecture (deliberate decision — do not flag):** FitBuddy uses a **BYO-key approach**: the end user enters their *own* Claude and Hevy API keys, which are stored exclusively in the local iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) and used only for that user's own calls, billed to that user's own account. No developer key is embedded in the binary. Anthropic's Usage Policy (AUP) does not prohibit this architecture — the "no keys in the client" guidance is a security best practice aimed at embedding *your own* key in shipped code, and it does not apply to the BYO-key case. Anthropic's best practice that "each user should obtain their own key" is in fact satisfied by this model. The third-party trust aspect is covered via the consent screen and the spending limit; certificate pinning is planned but not yet implemented for any host (open technical debt TD-4 in `docs/ARCHITECTURE.md`). **Direct-from-mobile calls with a locally stored user key are therefore intended and compliant here — no refactor to a backend proxy is required, and this should not be raised as a security issue.**
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
Art. 22 nDSG DSFA, or a full processing register — these are v1.0 / commercial-launch material.
Architecture rule: **never use a shared team key for external testers** (strict BYO-key only),
otherwise the team becomes the Anthropic "Customer", bears the cost, and re-imports the heavy
obligations. The final proportionality call rests with the BFH data protection office. Do not
re-raise DPA/DSFA/AUP as PoC blockers.


## Important Repository Contents (Selection)

| File              | Purpose | Instruction                                                                                                                                                                                                                                 |
|-------------------|---|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `README.md`       | Project overview and feature summary | &bull; Use this file to get an overview of the project (problem scope, solution to the problem), the scope, and the personas.<br>&bull; When adding/removing text in this file, use the German language                                          |
| `docs/REQUIREMENTS.md` | 15 user stories with acceptance criteria (MoSCoW v5) | &bull; Use this document to get all functional and non-functional requirements (sorted by MoSCoW), the out-of-scope requirements, and the top three non-functional requirements.<br>&bull; When adding/removing text in this file, use the German language.<br>&bull; Do NOT change or extend the existing chapter structure (1. User Stories with subsections 1.1 Must / 1.2 Should / 1.3 Could / 1.4 Won't, 2. MoSCoW-Priorisierung, 3. Nicht-funktionale Anforderungen, 4. Out of Scope, 5. Quality Attributes). Only edit content within existing chapters.<br>&bull; **Sync rule:** `docs/REQUIREMENTS.md` is the single source of truth for user stories and acceptance criteria. It must always be in sync with the corresponding GitHub Issues (US-1–US-15 in `fitbuddies-cas/fitbuddy`). Whenever a user story or acceptance criterion changes — in either place — update the other accordingly. |
| `docs/ARCHITECTURE.md` | System design, Swift data model, Connector interface, ADRs | &bull; Use this document to get an overview of the architecture of our app project.<br>&bull; When adding/removing text in this file, use the German language                                                                                    |
| `docs/adr/`           | Architecture Decision Records | &bull; Architecture decisions are stored in this directory.<br>&bull; Create and edit ADRs using the Nygard format (Title, Status, Context, Decision, Consequences). <br>&bull; When adding/removing text in this file, use the German language.                                                                         |

## Git Workflow

**Flow:** `feature/*` / `fix/*` → PR to **`develop`** (per task) → `develop` → `main` (1× weekly, Wed evening). **Never** commit directly to `develop` or `main` — always via PR.

| Rule | Default |
|---|---|
| **Permanent branches** | `main` (release-stable), `develop` (integration) |
| **Working branches** | `feature/task-<issue#>-short` or `fix/bug-<issue#>-short` (e.g. `feature/task-019-keychain-service`) |
| **PR Target (Base)** | `feature/*` & `fix/*` **always against `develop`** — never against `main` |
| **Merge rights** | All team members may merge |
| **PR Reviews** | Min. 1 approval (recommended 2) before merge |
| **Claude Pre-Review** | Reviewer triggers `/code-review` for larger PRs |
| **`develop` → `main`** | 1× weekly (Wednesday evening), as a bundled PR |
| **Pre-commit hook** | `.githooks/pre-commit` blocks direct commits to `main`/`develop`. It is opt-in per clone — run `git config core.hooksPath .githooks` once after cloning |

## Code Conventions

- **MVVM:** View (SwiftUI, no logic) → ViewModel (`@MainActor final class ObservableObject`) → Service (`actor`, API/Keychain) → Model (`struct Codable`)
- **Naming:** `WorkoutListView`, `WorkoutListViewModel`, `HevyService`, `Workout`
- **Folder-Structure (feature-first):** Each feature gets `Features/<Name>/` containing its `Views/` + ViewModel (e.g. `Features/Onboarding/`, `Features/Dashboard/`, `Features/Analysis/`). Cross-cutting code lives in `Core/` (`Accessibility/`, `Concurrency/`, `Connector/`, `DesignSystem/`, `KeyEntry/`, `Keychain/`, `LLM/`, `MockData/`, `Networking/`, `Persistence/`, `Privacy/`, `TrainingProfile/`); app entry & root navigation in `App/`. Add a `domain/`+`data/` split inside a folder **only where it genuinely has both** — for v0 that is only `Core/Connector/` (normalized `Activity` model vs `HevyConnector`/DTOs), not every feature. **Services** follow the same rule: a feature-specific service (e.g. `InferenceService`) lives in its feature folder; a shared/cross-feature service (e.g. `KeychainService`, `HevyConnector`, API client) lives under `Core/` in the matching subfolder.
- No force-unwrap. Async/await, not Combine. Keychain only in Services. One type per file.
- For every new `ViewModel` and `Service`, write corresponding unit tests in `FitBuddyTests/` using XCTest. Views do not require unit tests.
- **Run unit tests only when working locally** — `-skip-testing:FitBuddyUITests`. The XCUITests in `FitBuddyUITests/` boot a simulator and drive the app, which takes minutes per run and blocks the machine; never start them as part of ordinary local work, not even to verify a change that touches a screen. CI is where they belong: the `ui-test` job runs them on a PR into `main`, on a manual run, or when a PR carries the `ui-tests` label (#120, #148). Write and change UI tests locally as needed — just push them and let CI execute them, unless the user explicitly asks for a local run.
- All comments in the iOS code base must be in English, no other languages
- Before doing an UI task consult the design folder
- The text in the app has to be in english