import Foundation
import XCTest
@testable import FitBuddy

/// Test double for the detail read, so `WorkoutDetailViewModel` can be tested
/// without a SwiftData container.
///
/// `@MainActor` rather than `@unchecked Sendable`: `workoutDetail(id:)` is a
/// `nonisolated async` protocol requirement, so on a plain class it would run
/// on the global executor (SE-0338) — the counters below would be written off
/// the main actor while the test reads them on it. Isolating the stub makes
/// the single-actor claim true instead of merely silencing the diagnostic, and
/// an isolated `async` method is a legal witness for the requirement.
@MainActor
final class StubWorkoutDetailCache: WorkoutDetailReading {
    /// Sessions the cache knows about; anything else reads back as `nil`.
    var details: [WorkoutDetail] = []
    /// When set, the read throws instead of returning a session.
    var error: Error?
    /// Holds every call until `release()` — lets a test observe `.loading`.
    var gatesCalls = false

    /// The `id` argument of the last call.
    private(set) var requestedID: String?
    private(set) var callCount = 0

    private var gate: CheckedContinuation<Void, Never>?

    func workoutDetail(id: String) async throws -> WorkoutDetail? {
        requestedID = id
        callCount += 1

        if gatesCalls {
            await withCheckedContinuation { gate = $0 }
        }
        if let error { throw error }
        return details.first { $0.id == id }
    }

    /// Suspends until a call has reached the gate.
    ///
    /// Bounded so a wiring mistake fails the test instead of hanging it — and
    /// it has to fail *here*: returning without a gate would make `release()` a
    /// no-op, leaving the continuation to be created afterwards and never
    /// resumed, and the test would then hang on the read it is awaiting.
    func waitForCall() async {
        for _ in 0..<1_000 {
            if gate != nil { return }
            await Task.yield()
        }
        XCTFail("No call reached the gate")
    }

    /// Lets the gated call finish.
    func release() {
        gate?.resume()
        gate = nil
    }

    struct Failure: Error {}
}
