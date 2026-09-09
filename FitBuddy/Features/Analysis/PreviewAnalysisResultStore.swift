import Foundation

#if DEBUG
/// In-memory `AnalysisResultStoring` for SwiftUI previews (#117).
///
/// Debug-only: the shipped app always reads the real `AnalysisResultStore`.
/// Previews cannot spin up a SwiftData container per canvas, so the history
/// screen gets plain values — and a delete that only affects this array.
actor PreviewAnalysisResultStore: AnalysisResultStoring {
    private var entries: [AnalysisResultSnapshot]

    init(entries: [AnalysisResultSnapshot] = PreviewAnalysisResultStore.sample) {
        self.entries = entries
    }

    @discardableResult
    func save(text: String, generatedAt: Date, context: AnalysisContext) throws -> UUID {
        let entry = AnalysisResultSnapshot(
            id: UUID(),
            text: text,
            generatedAt: generatedAt,
            context: context,
            feedback: nil
        )
        entries.insert(entry, at: 0)
        return entry.id
    }

    func latest() throws -> AnalysisResultSnapshot? { entries.first }

    func recent(limit: Int) throws -> [AnalysisResultSnapshot] { Array(entries.prefix(limit)) }

    func delete(id: UUID) throws { entries.removeAll { $0.id == id } }

    func setFeedback(_ feedback: AnalysisFeedback?, for id: UUID) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries[index]
        entries[index] = AnalysisResultSnapshot(
            id: entry.id,
            text: entry.text,
            generatedAt: entry.generatedAt,
            context: entry.context,
            feedback: feedback
        )
    }

    func deleteAll() throws { entries = [] }

    /// Two analyses a week apart, one of them rated — enough for the list, the
    /// preview of a formatted text, and the verdict symbol.
    static let sample: [AnalysisResultSnapshot] = [
        AnalysisResultSnapshot(
            id: UUID(),
            text: """
            **Progressive overload**
            Bench press has sat at 60 kg for five sessions at the same rep count.

            - Add 2.5 kg on your next session and keep the reps
            - Give legs a second slot before adding upper-body volume
            """,
            generatedAt: .now.addingTimeInterval(-2 * 3_600),
            context: AnalysisContext(sessionCount: 12, window: .default),
            feedback: .helpful
        ),
        AnalysisResultSnapshot(
            id: UUID(),
            text: "Give legs a second slot in the week before you add upper-body volume.",
            generatedAt: .now.addingTimeInterval(-9 * 86_400),
            context: AnalysisContext(sessionCount: 4, window: AnalysisWindow(weeks: 8)),
            feedback: nil
        )
    ]
}
#endif
