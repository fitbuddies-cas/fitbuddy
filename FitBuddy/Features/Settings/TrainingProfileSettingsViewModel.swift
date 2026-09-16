import Foundation

/// Drives the training profile screen in Settings (US-13 AC5, #191): change
/// either answer, or remove the profile.
///
/// Unlike the onboarding step, every change is written as it is made. A
/// settings screen with a separate "save" step is one the user leaves without
/// pressing it — and for existing installs this screen is the only way to a
/// profile at all, so it has to behave like every other settings toggle.
@MainActor
final class TrainingProfileSettingsViewModel: ObservableObject {
    @Published private(set) var goal: TrainingGoal?
    @Published private(set) var experience: TrainingExperience?

    private let store: TrainingProfileStore

    init(store: TrainingProfileStore = TrainingProfileStore()) {
        self.store = store
    }

    /// Whether anything is set — what "Remove profile" has to act on.
    var hasProfile: Bool { goal != nil || experience != nil }

    func load() async {
        let stored = await store.profile
        goal = stored.goal
        experience = stored.experience
    }

    /// Selects a goal, or clears it when it is the one already selected — the
    /// same rule as in onboarding, for the same reason: there is no "none of
    /// these" row.
    func select(goal newGoal: TrainingGoal) async {
        goal = goal == newGoal ? nil : newGoal
        await persist()
    }

    func select(experience newExperience: TrainingExperience) async {
        experience = experience == newExperience ? nil : newExperience
        await persist()
    }

    /// Drops both answers. Recorded as a decision, not as a blank slate: the
    /// app then behaves as it does without a profile, and does not ask again.
    func remove() async {
        goal = nil
        experience = nil
        await store.removeProfile()
    }

    private func persist() async {
        let profile = TrainingProfile(goal: goal, experience: experience)
        if profile.isEmpty {
            // Clearing the last answer is a removal, and has to settle the
            // step the same way — see `TrainingProfileStore.removeProfile()`.
            await store.removeProfile()
        } else {
            await store.save(profile)
        }
    }
}
