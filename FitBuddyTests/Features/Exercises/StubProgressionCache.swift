import Foundation
@testable import FitBuddy

/// Test double for the progression read, so `ExerciseProgressionViewModel` can
/// be driven without a SwiftData container (#42).
///
/// Calls arrive from the ViewModel's `@MainActor` context, so the mutable
/// state below is only ever touched from one actor — hence `@unchecked`.
final class StubProgressionCache: ExerciseProgressionReading, @unchecked Sendable {
    /// Returned by every call. `nil` stands for "this movement is not in the
    /// window", which the screen tells apart from "no usable sets".
    var progression: ExerciseProgression?
    /// When set, the read throws instead of returning.
    var error: Error?

    /// The `since` argument of the last call — proves the 90-day boundary.
    private(set) var requestedSince: Date?
    private(set) var requestedID: String?
    private(set) var callCount = 0

    init(progression: ExerciseProgression? = nil) {
        self.progression = progression
    }

    func exerciseProgression(id: String, since date: Date) async throws -> ExerciseProgression? {
        callCount += 1
        requestedID = id
        requestedSince = date
        if let error { throw error }
        return progression
    }

    struct Failure: Error {}
}
