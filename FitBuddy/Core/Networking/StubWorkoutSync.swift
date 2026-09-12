import Foundation

// Test support: excluded from Release builds.
#if DEBUG

/// A workout sync that reaches no network (#120).
///
/// The dashboard syncs on its own as soon as onboarding lets it through. With
/// a stubbed key that call is the one thing standing between a UI test and the
/// dashboard: Hevy answers the fake key with 401, the app performs the hard
/// logout US-1 AC3 demands, and the test finds itself back on step 2 — a
/// correct app doing exactly the wrong thing for the test.
///
/// By default it caches nothing and reports success over an empty cache, which
/// lands the dashboard on its empty state — the honest picture for an account
/// that has no workouts here. Under `-fbSeedMockWorkouts` it writes the bundled
/// mock workouts instead, plus one extra session per sync after the first, so
/// a UI test can tell a pull-to-refresh that completed ("61 total") from one
/// that was cancelled ("60 total").
actor StubWorkoutSync: WorkoutSyncing {
    private let now: () -> Date
    private let delay: Duration
    private let seed: (store: WorkoutStore, activities: [Activity])?
    private var syncCount = 0

    /// - Parameters:
    ///   - delay: How long the stubbed sync takes. Zero for the onboarding UI
    ///     tests; a few seconds under `-fbSlowStubSync`, so a cancellation of
    ///     the calling task has something to interrupt — `Task.sleep` throws
    ///     `CancellationError` exactly as a cancelled request would.
    ///   - seed: Workouts to write into `store` as the Hevy window on every
    ///     sync, or `nil` to cache nothing.
    init(
        now: @escaping () -> Date = Date.init,
        delay: Duration = .zero,
        seed: (store: WorkoutStore, activities: [Activity])? = nil
    ) {
        self.now = now
        self.delay = delay
        self.seed = seed
    }

    @discardableResult
    func syncRecentWorkouts() async throws -> SyncResult {
        syncCount += 1
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        let syncedAt = now()
        var count = 0
        if let seed {
            // Every sync after the first brings one more session, dated now,
            // so the session count on screen shows whether a refresh landed.
            let extras = (1..<syncCount).map { index in
                Activity(id: "stub-extra-\(index)", title: "Refreshed session \(index)", startTime: syncedAt)
            }
            let activities = seed.activities + extras
            try await seed.store.replaceCachedWorkouts(with: activities)
            count = activities.count
        }
        return SyncResult(
            workoutCount: count,
            syncedAt: syncedAt,
            windowStart: TrainingWindow.start(endingAt: syncedAt)
        )
    }
}

#endif
