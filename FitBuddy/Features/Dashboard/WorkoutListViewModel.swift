import Foundation

/// Drives the dashboard's workout list and its 90-day metrics (US-2).
///
/// Reads the SwiftData cache exclusively — it never calls the Hevy API. The
/// sync that fills the cache is `HevyService`'s job (#25); keeping the two
/// apart is what makes AC2 work, because the dashboard renders the same way
/// whether the last sync just succeeded or the device has been offline for
/// days. `lastSync` tells the user which of the two it is.
@MainActor
final class WorkoutListViewModel: ObservableObject {
    @Published private(set) var state: WorkoutListState = .loading
    /// Timestamp of the last successful sync, or `nil` if none ever completed
    /// — the banner data for US-2 AC2.
    @Published private(set) var lastSync: Date?

    private let cache: WorkoutSummaryReading
    private let timestamps: SyncTimestampStore
    private let calendar: Calendar
    private let now: () -> Date

    /// - Parameters:
    ///   - cache: Read access to the cached window (`WorkoutStore` in the app).
    ///   - now: Injectable clock, so the window boundary is testable.
    init(
        cache: WorkoutSummaryReading,
        timestamps: SyncTimestampStore = SyncTimestampStore(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.cache = cache
        self.timestamps = timestamps
        self.calendar = calendar
        self.now = now
    }

    /// Loads the window from the cache and recomputes the metrics.
    ///
    /// Safe to call again after a sync: the previous content stays on screen
    /// while the read runs, so a refresh never flashes an empty dashboard.
    func load() async {
        lastSync = await timestamps.lastSync()

        let windowStart = TrainingWindow.start(endingAt: now(), calendar: calendar)
        do {
            let summaries = try await cache.workoutSummaries(since: windowStart)
            state = summaries.isEmpty
                ? .empty
                : .loaded(
                    workouts: summaries,
                    metrics: DashboardMetrics(summaries: summaries, calendar: calendar)
                )
        } catch {
            state = .failed
        }
    }
}
