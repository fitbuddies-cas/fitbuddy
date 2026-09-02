import Foundation
@testable import FitBuddy

/// Test double for the detail read, so `WorkoutDetailViewModel` can be tested
/// without a SwiftData container.
///
/// Calls arrive from the ViewModel's `@MainActor` context, so the mutable
/// state below is only ever touched from one actor — hence `@unchecked`.
final class StubWorkoutDetailCache: WorkoutDetailReading, @unchecked Sendable {
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
    func waitForCall() async {
        // Bounded so a wiring mistake fails the test instead of hanging it.
        for _ in 0..<1_000 where gate == nil {
            await Task.yield()
        }
    }

    /// Lets the gated call finish.
    func release() {
        gate?.resume()
        gate = nil
    }

    struct Failure: Error {}
}
