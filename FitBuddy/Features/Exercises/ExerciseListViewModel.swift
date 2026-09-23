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
/// a filter that reacts while typing). The muscle-group filter (AC2) rides the
/// same in-memory pass and combines with the search (AC3).
@MainActor
final class ExerciseListViewModel: ObservableObject {
    @Published private(set) var state: ExerciseListState = .loading
    /// The search field's text, bound by the view.
    @Published var searchText: String = ""
    /// Muscle groups the user has picked in the filter row. Empty means "no
    /// muscle filter" — the chips do not narrow the list until one is tapped.
    @Published var selectedMuscleGroups: Set<MuscleGroup> = []

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
    /// muscle-group filter and then the search text (AC3 — the two combine).
    ///
    /// Muscle groups use OR logic (AC2): with Chest and Back selected a
    /// movement shows if it belongs to either. Empty for a filter that matches
    /// nothing — which the view tells apart from an empty window through
    /// `hasNoMatches`.
    var visibleExercises: [ExerciseSummary] {
        guard case .loaded(let exercises) = state else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return exercises.filter { exercise in
            let matchesGroup = selectedMuscleGroups.isEmpty
                || selectedMuscleGroups.contains(exercise.muscleGroup)
            let matchesQuery = query.isEmpty || exercise.matches(query: query)
            return matchesGroup && matchesQuery
        }
    }

    /// The muscle groups offered as filter chips: every group FitBuddy
    /// classifies movements into, in the app's canonical order (AC1).
    var filterGroups: [MuscleGroup] { MuscleGroup.allCases }

    /// Whether the search field and the filter row belong on screen: only once
    /// the window has loaded with movements in it. Over an empty or failed
    /// window they would be controls with nothing to act on.
    var showsFilterControls: Bool {
        guard case .loaded = state else { return false }
        return true
    }

    /// Whether a search term or a muscle-group chip is currently narrowing the
    /// list.
    var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !selectedMuscleGroups.isEmpty
    }

    /// Whether the active filter — search, chips, or both — matched nothing:
    /// the «No exercises found» case of AC1/AC2, as opposed to a window with no
    /// training in it at all.
    var hasNoMatches: Bool {
        guard case .loaded = state else { return false }
        return isFiltering && visibleExercises.isEmpty
    }

    /// Adds or removes a muscle group from the filter — one chip tap.
    func toggle(_ group: MuscleGroup) {
        if selectedMuscleGroups.contains(group) {
            selectedMuscleGroups.remove(group)
        } else {
            selectedMuscleGroups.insert(group)
        }
    }

    /// Loads the window from the cache — the screen's `.task` and the "Try
    /// again" button of the failure card.
    ///
    /// Never throws: every outcome lands in `state`, so the screen always says
    /// something. Publishes `.loading` first unless the rows are already on
    /// screen: the list is a tab root since #264, and its `.task` re-runs on
    /// every return to the tab so a sync in between shows up — dropping to a
    /// spinner each time would flash the screen and dismiss the search field.
    /// A retry after a failure still goes through `.loading`, so a retry that
    /// fails again is visible as a retry instead of leaving the screen
    /// untouched.
    func load() async {
        if case .loaded = state {} else {
            state = .loading
        }
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
