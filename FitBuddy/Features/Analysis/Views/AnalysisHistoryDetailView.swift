import SwiftUI

/// One stored analysis in full, pushed from the history list (US-3 AC11,
/// #117).
///
/// The recommendation and the basis it rests on, and nothing else: no "New
/// analysis" — a new run belongs to the analysis screen, not to an old text.
struct AnalysisHistoryDetailView: View {
    let entry: AnalysisResultSnapshot
    /// The instant the list rendered against, so the age here matches the row
    /// the user tapped.
    let now: Date

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // The same cards the user saw when the row stores a report
                // (#176); prose for every row from before V3 (US-14 AC6).
                AnalysisResultView(
                    outcome: AnalysisOutcome(stored: entry),
                    context: entry.context,
                    // Rows from before #176 did not store the provider, so
                    // their badge stays the bare "AI" rather than naming one
                    // on a guess.
                    attribution: entry.provider.map(AnalysisAttribution.init(first:)),
                    age: SyncTimeFormatter.relative(since: entry.generatedAt, now: now)
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.fbBackground)
        .navigationTitle("Analysis")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
/// A stored report renders its cards, as on the analysis screen (design 3.7b).
#Preview("Report") {
    NavigationStack {
        AnalysisHistoryDetailView(
            entry: AnalysisResultSnapshot(
                id: UUID(),
                text: AnalysisReportSamples.progress.summary,
                generatedAt: .now.addingTimeInterval(-3 * 86_400),
                context: AnalysisContext(sessionCount: 12, window: .default),
                report: AnalysisReportSamples.progress,
                provider: .claude
            ),
            now: .now
        )
    }
}

/// A stored report without cards: lead and the full analysis, open (#170).
#Preview("Thin report") {
    NavigationStack {
        AnalysisHistoryDetailView(
            entry: AnalysisResultSnapshot(
                id: UUID(),
                text: AnalysisReportSamples.thin.summary,
                generatedAt: .now.addingTimeInterval(-86_400),
                context: AnalysisContext(sessionCount: 2, window: .default),
                report: AnalysisReportSamples.thin,
                provider: .mistral
            ),
            now: .now
        )
    }
}

/// A row stored before V3: prose, and a bare "AI" badge (US-14 AC6).
#Preview("Prose") {
    NavigationStack {
        AnalysisHistoryDetailView(
            entry: AnalysisResultSnapshot(
                id: UUID(),
                text: """
                You trained 14 times in the last four weeks.

                **Progressive overload**
                Bench press has sat at 60 kg for five sessions.

                - Add 2.5 kg on your next session and keep the reps
                - Give legs a second slot before adding upper-body volume
                """,
                generatedAt: .now.addingTimeInterval(-3 * 86_400),
                context: AnalysisContext(sessionCount: 12, window: .default)
            ),
            now: .now
        )
    }
}
#endif
