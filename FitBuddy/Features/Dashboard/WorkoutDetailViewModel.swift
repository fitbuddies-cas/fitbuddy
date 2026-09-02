import Foundation

/// Drives the workout detail screen: one cached session with its exercises and
/// sets (US-2 AC1, #98).
///
/// Reads the cache and nothing else — no sync, no Hevy call. Everything on
/// screen was already on the device when the row was tapped, which is why
/// going back to the dashboard cannot cost a request.
@MainActor
final class WorkoutDetailViewModel: ObservableObject {
    @Published private(set) var state: WorkoutDetailState = .loading

    /// The session this screen was opened for.
    let workoutID: String

    private let cache: WorkoutDetailReading

    /// - Parameters:
    ///   - cache: Read access to the cached session (`WorkoutStore` in the app).
    ///   - workoutID: Hevy's id of the tapped session.
    init(cache: WorkoutDetailReading, workoutID: String) {
        self.cache = cache
        self.workoutID = workoutID
    }

    /// Loads the session — the screen's `.task`.
    ///
    /// Never throws: every outcome lands in `state`, so the screen always says
    /// something. A read that comes back empty is `.missing`, not `.failed`.
    func load() async {
        do {
            let detail = try await cache.workoutDetail(id: workoutID)
            guard !Task.isCancelled else { return }
            state = detail.map(WorkoutDetailState.loaded) ?? .missing
        } catch {
            // A cancelled read says nothing about the cache — the user simply
            // navigated back before it returned, and publishing `.failed`
            // would leave an error behind on a screen nobody is looking at.
            guard !Task.isCancelled, !error.isCancellation else { return }
            state = .failed
        }
    }
}
