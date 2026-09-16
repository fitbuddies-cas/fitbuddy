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
/// mock workouts instead, plus one extra session per completed sync after the
/// first, so a UI test can tell a pull-to-refresh that completed ("61 total")
/// from one that never landed ("60 total").
actor StubWorkoutSync: WorkoutSyncing {
    /// What a seeded launch writes on every sync (#150).
    struct Seed: Sendable {
        let store: WorkoutStore
        /// Written after the cache, as `WorkoutSyncService` does. Without it
        /// `lastSync` stays `nil` and the status strip would flag the seeded
        /// window as never synced — a stale-source warning over a full
        /// dashboard (US-8).
        let timestamps: SyncTimestampStore
        let activities: [Activity]
    }

    private let now: () -> Date
    private let delay: Duration
    private let seed: Seed?
    /// Syncs that got past the sleep — the ones that wrote, if seeded.
    private var syncCount = 0

    /// - Parameters:
    ///   - delay: How long the stubbed sync takes. Zero for the onboarding UI
    ///     tests; a few seconds under `-fbSlowStubSync`, so a pull-to-refresh
    ///     ends its gesture before the sync does (#150) and a newer sync has
    ///     something to displace — `Task.sleep` throws `CancellationError`
    ///     exactly as a cancelled request would.
    ///   - seed: The window to write on every sync, or `nil` to cache nothing.
    init(
        now: @escaping () -> Date = Date.init,
        delay: Duration = .zero,
        seed: Seed? = nil
    ) {
        self.now = now
        self.delay = delay
        self.seed = seed
    }

    @discardableResult
    func syncRecentWorkouts() async throws -> SyncResult {
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        // Counted only once the sleep is through. A sync a newer one displaced
        // while it slept never writes, and must not use up a number: the UI
        // test reads the count off the screen as a literal "61 total", and a
        // displaced launch sync would otherwise make the refresh show 62.
        syncCount += 1
        let syncedAt = now()
        var count = 0
        if let seed {
            // Every sync after the first brings one more session, dated now,
            // so the session count on screen shows whether a refresh landed.
            let extras = (1..<syncCount).map { index in
                Activity(id: "stub-extra-\(index)", title: "Refreshed session \(index)", startTime: syncedAt)
            }
            let activities = seed.activities + extras
            try await seed.store.replaceCachedWorkouts(from: .hevy, with: activities)
            await seed.timestamps.setLastSync(syncedAt)
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
