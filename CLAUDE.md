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


## Important Repository Contents (Selection)

| File              | Purpose | Instruction                                                                                                                                                                                                                                 |
|-------------------|---|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `README.md`       | Project overview and feature summary | &bull; Use this file to get an overview of the project (problem scope, solution to the problem), the scope, and the personas.<br>&bull; When adding/removing text in this file, use the German language                                          |
| `REQUIREMENTS.md` | 12 user stories with acceptance criteria (MoSCoW v5) | &bull; Use this document to get all functional and non-functional requirements (sorted by MoSCoW), the out-of-scope requirements, and the top three non-functional requirements.<br>&bull; When adding/removing text in this file, use the German language.<br>&bull; Do NOT change or extend the existing chapter structure (1. User Stories with subsections 1.1 Must / 1.2 Should / 1.3 Could / 1.4 Won't, 2. MoSCoW-Priorisierung, 3. Nicht-funktionale Anforderungen, 4. Out of Scope, 5. Quality Attributes). Only edit content within existing chapters. |
| `ARCHITECTURE.md` | System design, Swift data model, Connector interface, ADRs | &bull; Use this document to get an overview of the architecture of our app project.<br>&bull; When adding/removing text in this file, use the German language                                                                                    |
| `ADRs/`           | Architecture Decision Records | &bull; Architecture decisions are stored in this directory.<br>&bull; Create and edit ADRs using the Nygard format (Title, Status, Context, Decision, Consequences). <br>&bull; When adding/removing text in this file, use the German language.                                                                         |

## Code Conventions

### Architecture: MVVM
- **View** — SwiftUI only, no business logic. Binds to ViewModel via `@StateObject` / `@ObservedObject`.
- **ViewModel** — `@MainActor final class`, conforms to `ObservableObject`. Owns state (`@Published`) and calls Services.
- **Service** — pure Swift `actor` or `struct`. Handles API calls, Keychain, persistence. No SwiftUI imports.
- **Model** — plain `struct`, `Codable`, value semantics.

### Naming
| Layer     | Suffix       | Example                  |
|-----------|--------------|--------------------------|
| View | `View` | `WorkoutDetailView` |
| ViewModel | `ViewModel` | `WorkoutDetailViewModel` |
| Service | `Service` | `HevyService` |
| Model | _(none)_ | `Workout`, `Exercise` |

### File Structure
```
FitBuddy/
├── Views/
│   └── Workout/
│       └── WorkoutDetailView.swift
├── ViewModels/
│   └── WorkoutDetailViewModel.swift
├── Services/
│   ├── HevyService.swift
│   └── ClaudeService.swift
└── Models/
    └── Workout.swift
```

### Example
```swift
// Model
struct Workout: Codable, Identifiable {
    let id: String
    let title: String
    let startTime: Date
}

// Service
actor HevyService {
    func fetchWorkouts() async throws -> [Workout] { … }
}

// ViewModel
@MainActor
final class WorkoutListViewModel: ObservableObject {
    @Published var workouts: [Workout] = []
    @Published var isLoading = false

    private let hevyService: HevyService

    init(hevyService: HevyService = HevyService()) {
        self.hevyService = hevyService
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        workouts = (try? await hevyService.fetchWorkouts()) ?? []
    }
}

// View
struct WorkoutListView: View {
    @StateObject private var viewModel = WorkoutListViewModel()

    var body: some View {
        List(viewModel.workouts) { workout in
            Text(workout.title)
        }
        .task { await viewModel.load() }
    }
}
```

### Rules
- No force-unwrap (`!`) — use `guard let` or `try?`.
- Async/await over Combine for networking.
- Keychain access only inside a `Service`, never in a View or ViewModel.
- One type per file.