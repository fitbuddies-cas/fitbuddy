import Foundation
@testable import FitBuddy

/// Wraps a real `AnalysisResultStoring` and lets a test hold `save` open.
///
/// Used to inspect what the screen shows *while* a finished run is being
/// persisted — the window in which a stale `cooldownMessage` used to offer
/// "New analysis" for a run `start()` would immediately refuse.
actor GatedAnalysisResultStore: AnalysisResultStoring {
    private let wrapped: any AnalysisResultStoring
    private var entered: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    private var didEnter = false
    private var isReleased = false

    init(wrapping wrapped: any AnalysisResultStoring) {
        self.wrapped = wrapped
    }

    /// Suspends until `save` is inside the gate.
    func waitForSave() async {
        guard !didEnter else { return }
        await withCheckedContinuation { entered = $0 }
    }

    /// Lets the pending (or next) `save` run to completion.
    func releaseSave() {
        isReleased = true
        release?.resume()
        release = nil
    }

    func save(text: String, generatedAt: Date, context: AnalysisContext) async throws {
        didEnter = true
        entered?.resume()
        entered = nil
        if !isReleased {
            await withCheckedContinuation { release = $0 }
        }
        try await wrapped.save(text: text, generatedAt: generatedAt, context: context)
    }

    func latest() async throws -> AnalysisResultSnapshot? {
        try await wrapped.latest()
    }

    func deleteAll() async throws {
        try await wrapped.deleteAll()
    }
}
