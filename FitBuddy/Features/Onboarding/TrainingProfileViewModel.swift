import Foundation

/// Drives the training profile screen (US-13, step 4): two questions, both
/// optional, and a way past them.
///
/// Nothing in the app depends on an answer. Without a profile the analysis
/// runs exactly as it does today (#192), which is what lets the step be
/// skippable and what keeps existing users — who never see it — unaffected.
@MainActor
final class TrainingProfileViewModel: ObservableObject {
    /// The answers so far. Selecting is immediate and local; nothing is
    /// written until the user confirms, so backing out of the screen cannot
    /// leave half a profile behind.
    @Published var goal: TrainingGoal?
    @Published var experience: TrainingExperience?
    @Published private(set) var state: TrainingProfileState = .unknown

    /// Invoked on an active decision — saved or skipped, not on a bootstrap
    /// restore — letting the coordinator finish onboarding.
    var onFinished: (() -> Void)?

    private let store: TrainingProfileStore

    init(store: TrainingProfileStore = TrainingProfileStore()) {
        self.store = store
    }

    /// Whether the confirm button does anything: at least one question
    /// answered. With neither, "Skip for now" is the honest way out.
    var canSave: Bool { goal != nil || experience != nil }

    /// Resolves `.unknown` from what is stored, so a user returning to the
    /// step mid-onboarding sees their previous answers rather than a blank
    /// screen.
    func bootstrap() async {
        guard state == .unknown else { return }
        let stored = await store.profile
        goal = stored.goal
        experience = stored.experience
        if await store.isSkipped {
            state = .skipped
        } else {
            state = stored.isEmpty ? .idle : .saved
        }
    }

    func save() async {
        guard canSave else { return }
        await store.save(TrainingProfile(goal: goal, experience: experience))
        state = .saved
        onFinished?()
    }

    /// Continue without answering (AC2). Recorded, so the step does not
    /// reappear on the next cold start.
    func skip() async {
        await store.setSkipped()
        state = .skipped
        onFinished?()
    }

    /// Returns the screen to fresh questions — "delete all data" (#83) and the
    /// hard logout both restart onboarding, and a profile left in the fields
    /// would belong to the previous session.
    func reset() {
        goal = nil
        experience = nil
        state = .unknown
    }
}
