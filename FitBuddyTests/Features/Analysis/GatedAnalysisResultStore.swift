import Foundation
@testable import FitBuddy

/// Wraps a real `AnalysisResultStoring` and lets a test hold `save` open.
///
/// Used to inspect what the screen shows *while* a finished run is being
/// persisted — the run must still read as in flight, so "New analysis"
/// cannot start a second one before the first has stored its answer.
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

    @discardableResult
    func save(
        text: String,
        report: ValidatedAnalysisReport?,
        provider: LLMProvider?,
        validationLog: AnalysisValidationLog?,
        generatedAt: Date,
        context: AnalysisContext
    ) async throws -> UUID {
        didEnter = true
        entered?.resume()
        entered = nil
        if !isReleased {
            await withCheckedContinuation { release = $0 }
        }
        return try await wrapped.save(
            text: text,
            report: report,
            provider: provider,
            validationLog: validationLog,
            generatedAt: generatedAt,
            context: context
        )
    }

    func latest() async throws -> AnalysisResultSnapshot? {
        try await wrapped.latest()
    }

    func recent(limit: Int) async throws -> [AnalysisResultSnapshot] {
        try await wrapped.recent(limit: limit)
    }

    func delete(id: UUID) async throws {
        try await wrapped.delete(id: id)
    }

    func deleteAll() async throws {
        try await wrapped.deleteAll()
    }
}
