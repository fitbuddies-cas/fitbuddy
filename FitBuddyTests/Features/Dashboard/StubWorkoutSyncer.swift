import Foundation
@testable import FitBuddy

/// Test double for the Hevy sync, so `WorkoutListViewModel` can be driven
/// through every offline case without a network stub.
///
/// Calls arrive from the ViewModel's `@MainActor` context, so the mutable
/// state below is only ever touched from one actor — hence `@unchecked`.
final class StubWorkoutSyncer: WorkoutSyncing, @unchecked Sendable {
    /// When set, the sync throws instead of succeeding.
    var error: Error?
    /// Result handed back on success.
    var result = SyncResult(workoutCount: 0, syncedAt: .distantPast, windowStart: .distantPast)
    /// Runs before the sync returns — lets a test swap the cache content the
    /// way a real sync would.
    var onSync: (() -> Void)?
    /// Holds the first call until `releaseFirstCall()`, for overlapping syncs.
    var gatesFirstCall = false

    private(set) var callCount = 0

    private var gate: CheckedContinuation<Void, Never>?

    @discardableResult
    func syncRecentWorkouts() async throws -> SyncResult {
        callCount += 1
        let call = callCount

        if gatesFirstCall && call == 1 {
            await withCheckedContinuation { gate = $0 }
        }
        onSync?()
        if let error { throw error }
        return result
    }

    /// Suspends until the first call has reached the gate.
    ///
    /// `@MainActor` on purpose: the gated sync only reaches the gate after the
    /// ViewModel's main-actor cache read, and yielding from the main actor is
    /// what hands it the time to get there. Polling from a background executor
    /// races that read and can run out of yields before the call arrives.
    @MainActor
    func waitForFirstCall() async {
        // Bounded so a wiring mistake fails the test instead of hanging it.
        for _ in 0..<10_000 where gate == nil {
            await Task.yield()
        }
    }

    /// Lets the gated first call finish.
    func releaseFirstCall() {
        gate?.resume()
        gate = nil
    }
}
