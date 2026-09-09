import Foundation
import OSLog

/// Drives the history screen: the stored analyses, newest first, and the swipe
/// that removes one (US-3 AC11, #117).
///
/// Deliberately thin next to `AnalysisViewModel`. Nothing here runs, streams or
/// costs anything — the texts were paid for when they were written, and this
/// screen only reads them back.
@MainActor
final class AnalysisHistoryViewModel: ObservableObject {
    /// The stored analyses, newest first. Empty until `load()` has run, which
    /// is also the state the empty screen renders.
    @Published private(set) var entries: [AnalysisResultSnapshot] = []
    /// Whether the list has been read at least once, so the empty screen does
    /// not flash up in front of a list that is about to arrive.
    @Published private(set) var isLoaded = false
    /// Set when the store could not be read or a delete failed. The list stays
    /// on screen underneath — a recommendation that is still there is worth
    /// more to the user than an error page.
    @Published private(set) var failure: String?

    private let store: any AnalysisResultStoring

    private let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "Analysis")

    init(store: any AnalysisResultStoring) {
        self.store = store
    }

    /// Reads the history. Called by the screen's `.task`, and again after a
    /// delete, so the list never drifts from the store.
    func load() async {
        do {
            entries = try await store.recent(limit: AnalysisHistoryLimit.rows)
            failure = nil
        } catch {
            logger.error("Analysis history not readable: \(error, privacy: .public)")
            failure = "Your saved analyses could not be read."
        }
        isLoaded = true
    }

    /// Removes exactly one analysis — the swipe of US-3 AC11.
    ///
    /// The row is dropped from the list first, so the swipe finishes at the
    /// speed of the gesture rather than at the speed of the store; the reload
    /// behind it is what makes the two agree again.
    func delete(id: UUID) async {
        let previous = entries
        entries.removeAll { $0.id == id }
        do {
            try await store.delete(id: id)
            failure = nil
        } catch {
            logger.error("Analysis not deleted: \(error, privacy: .public)")
            // Put back what is demonstrably still stored: a row that vanished
            // from the screen but not from the device is the one outcome a
            // deletion must never have.
            entries = previous
            failure = "This analysis could not be deleted."
        }
    }
}
