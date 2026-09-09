import Foundation

/// Drives the exercise list: every movement of the cached 90-day window, with
/// a live text search over it (US-7 AC1, #37).
///
/// Reads the cache and nothing else — no sync, no Hevy call. The dashboard
/// owns the sync; this screen shows what that sync already put on the device.
///
/// The search filters in memory rather than in a `FetchDescriptor`: the window
/// holds a few dozen movements, and a predicate per keystroke would put a
/// SwiftData round trip between the user's typing and the list (AC1 asks for
/// a filter that reacts while typing).
@MainActor
final class ExerciseListViewModel: ObservableObject {
    @Published private(set) var state: ExerciseListState = .loading
    /// The search field's text, bound by the view.
    @Published var searchText: String = ""

    private let cache: ExerciseSummaryReading
    private let calendar: Calendar
    private let now: () -> Date

    /// - Parameters:
    ///   - cache: Read access to the cached window (`WorkoutStore` in the app).
    ///   - now: Injectable clock, so the window boundary is testable.
    init(
        cache: ExerciseSummaryReading,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.cache = cache
        self.calendar = calendar
        self.now = now
    }

    /// The rows the list renders: everything the window holds, narrowed by the
    /// search text.
    ///
    /// Empty for a query that matches nothing — which the view tells apart
    /// from an empty window through `hasNoSearchMatches`.
    var visibleExercises: [ExerciseSummary] {
        guard case .loaded(let exercises) = state else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return exercises }
        return exercises.filter { $0.matches(query: query) }
    }

    /// Whether the user typed a query that no movement matches — the
    /// «No exercises found» case of AC1, as opposed to a window with no
    /// training in it at all.
    var hasNoSearchMatches: Bool {
        guard case .loaded = state else { return false }
        return !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && visibleExercises.isEmpty
    }

    /// Loads the window from the cache — the screen's `.task` and the "Try
    /// again" button of the failure card.
    ///
    /// Never throws: every outcome lands in `state`, so the screen always says
    /// something. Publishes `.loading` first, so a retry that fails again is
    /// visible as a retry instead of leaving the screen untouched.
    func load() async {
        state = .loading
        let windowStart = TrainingWindow.start(endingAt: now(), calendar: calendar)
        do {
            let exercises = try await cache.exerciseSummaries(since: windowStart)
            guard !Task.isCancelled else { return }
            state = exercises.isEmpty ? .empty : .loaded(exercises)
        } catch {
            // A cancelled read says nothing about the cache — the user simply
            // navigated back before it returned.
            guard !Task.isCancelled, !error.isCancellation else { return }
            state = .failed
        }
    }
}

private extension ExerciseSummary {
    /// Whether the movement's title contains `query`.
    ///
    /// Case- and diacritic-insensitive (AC1): the user types "bench", not
    /// "Bench Press (Barbell)", and searching their own history should not
    /// depend on how Hevy capitalised it.
    func matches(query: String) -> Bool {
        title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
