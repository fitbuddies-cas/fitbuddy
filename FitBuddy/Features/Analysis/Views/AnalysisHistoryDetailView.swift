import SwiftUI

/// One stored analysis in full, pushed from the history list (US-3 AC11,
/// #117).
///
/// The recommendation and the basis it rests on, and nothing else: no feedback
/// bar and no "New analysis". A verdict belongs to the recommendation the user
/// has just read on the analysis screen — offering the buttons again weeks
/// later would collect an opinion about a text whose training data has long
/// moved on.
struct AnalysisHistoryDetailView: View {
    let entry: AnalysisResultSnapshot
    /// The instant the list rendered against, so the age here matches the row
    /// the user tapped.
    let now: Date

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                AnalysisContextView(context: entry.context)
                AnalysisResultView(
                    text: entry.text,
                    // The provider is not stored, so the badge stays the bare
                    // "AI" rather than naming one on a guess.
                    attribution: nil,
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
#Preview {
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
                context: AnalysisContext(sessionCount: 12, window: .default),
                feedback: .helpful
            ),
            now: .now
        )
    }
}
#endif
