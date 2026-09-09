import Foundation
import XCTest
@testable import FitBuddy

/// Test double for the Hevy sync, so `WorkoutListViewModel` can be driven
/// through every offline case without a network stub.
///
/// An `actor`, mirroring `WorkoutSyncService`: `WorkoutSyncing.syncRecentWorkouts()`
/// is a nonisolated `async` requirement, so its body runs on the cooperative
/// pool while the tests read `callCount` and swap `error` from the main actor.
/// A plain class with `@unchecked Sendable` would be covering that up rather
/// than documenting anything.
actor StubWorkoutSyncer: WorkoutSyncing {
    private var error: Error?
    private var result = SyncResult(workoutCount: 0, syncedAt: .distantPast, windowStart: .distantPast)
    private var gatesFirstCall = false
    /// Written on every successful sync, mirroring `WorkoutSyncService`: the
    /// dashboard reads its timestamp back out of the store, not out of the
    /// `SyncResult`, so a test about US-10 AC1 needs the store to move.
    private var timestamps: SyncTimestampStore?

    private(set) var callCount = 0

    /// Holds the gated first call until `releaseFirstCall()`.
    private var gate: CheckedContinuation<Void, Never>?
    /// Resumes `waitForFirstCall()` once the gated call has arrived.
    private var arrival: CheckedContinuation<Void, Never>?
    private var firstCallArrived = false

    /// When set, the sync throws instead of succeeding.
    func setError(_ error: Error?) {
        self.error = error
    }

    func setResult(_ result: SyncResult) {
        self.result = result
    }

    /// Makes a successful sync record `result.syncedAt`, as the real service
    /// does once the fetched window has been cached.
    func recordSyncs(in timestamps: SyncTimestampStore) {
        self.timestamps = timestamps
    }

    /// Makes the next call block until `releaseFirstCall()`, so a test can
    /// drive two overlapping syncs deterministically.
    func gateFirstCall() {
        gatesFirstCall = true
    }

    @discardableResult
    func syncRecentWorkouts() async throws -> SyncResult {
        callCount += 1

        if gatesFirstCall && callCount == 1 {
            firstCallArrived = true
            arrival?.resume()
            arrival = nil
            await withCheckedContinuation { gate = $0 }
        }

        if let error { throw error }
        await timestamps?.setLastSync(result.syncedAt)
        return result
    }

    /// Suspends until the gated first call has reached the gate.
    ///
    /// Signalled, not polled: a bounded yield loop can run out of yields before
    /// the call arrives, and then hands back control as if it had waited — the
    /// release below finds nothing to release and the test hangs on a call that
    /// never gets woken.
    func waitForFirstCall() async {
        guard !firstCallArrived else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    /// Lets the gated first call finish. Fails loudly rather than silently
    /// doing nothing, which would leave that call suspended forever.
    func releaseFirstCall(file: StaticString = #filePath, line: UInt = #line) {
        guard let gate else {
            return XCTFail("No gated sync is waiting to be released", file: file, line: line)
        }
        gate.resume()
        self.gate = nil
    }
}
