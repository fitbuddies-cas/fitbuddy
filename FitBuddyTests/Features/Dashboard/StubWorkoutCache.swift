import Foundation
@testable import FitBuddy

/// Test double for the cache read, so `WorkoutListViewModel` can be tested
/// without a SwiftData container.
///
/// Calls arrive from the ViewModel's `@MainActor` context, so the mutable
/// state below is only ever touched from one actor — hence `@unchecked`.
final class StubWorkoutCache: WorkoutSummaryReading, @unchecked Sendable {
    /// Summaries returned by every call, unless `results` is set.
    var summaries: [WorkoutSummary] = []
    /// One entry per call, when the test needs each call to answer differently.
    var results: [[WorkoutSummary]] = []
    /// When set, the read throws instead of returning summaries.
    var error: Error?
    /// Holds the first call until `releaseFirstCall()` — lets a test drive two
    /// overlapping loads deterministically.
    var gatesFirstCall = false

    /// The `since` argument of the last call — proves the 90-day boundary.
    private(set) var requestedSince: Date?
    private(set) var callCount = 0

    private var gate: CheckedContinuation<Void, Never>?

    func workoutSummaries(since date: Date) async throws -> [WorkoutSummary] {
        requestedSince = date
        callCount += 1
        let call = callCount

        if gatesFirstCall && call == 1 {
            await withCheckedContinuation { gate = $0 }
        }
        if let error { throw error }
        return results.isEmpty ? summaries : results[min(call - 1, results.count - 1)]
    }

    /// Suspends until the first call has reached the gate.
    func waitForFirstCall() async {
        // Bounded so a wiring mistake fails the test instead of hanging it.
        for _ in 0..<1_000 where gate == nil {
            await Task.yield()
        }
    }

    /// Lets the gated first call finish.
    func releaseFirstCall() {
        gate?.resume()
        gate = nil
    }

    struct Failure: Error {}
}
