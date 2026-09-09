import Foundation

// Test support: excluded from Release builds.
#if DEBUG

/// A workout sync that reaches no network and caches nothing (#120).
///
/// The dashboard syncs on its own as soon as onboarding lets it through. With
/// a stubbed key that call is the one thing standing between a UI test and the
/// dashboard: Hevy answers the fake key with 401, the app performs the hard
/// logout US-1 AC3 demands, and the test finds itself back on step 2 — a
/// correct app doing exactly the wrong thing for the test.
///
/// Reporting success over an empty cache lands the dashboard on its empty
/// state, which is the honest picture for an account that has no workouts here.
actor StubWorkoutSync: WorkoutSyncing {
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    @discardableResult
    func syncRecentWorkouts() async throws -> SyncResult {
        let syncedAt = now()
        return SyncResult(
            workoutCount: 0,
            syncedAt: syncedAt,
            windowStart: TrainingWindow.start(endingAt: syncedAt)
        )
    }
}

#endif
