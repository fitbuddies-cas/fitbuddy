import SwiftUI

/// One stored analysis in the history list (US-3 AC11, #117).
///
/// Presentational only — `AnalysisHistoryView` wraps it in the
/// `NavigationLink` that opens the full text and in the swipe that deletes it.
/// Like `WorkoutSessionRow` it spells its own accessibility label out, so the
/// announcement is a sentence rather than the fragments the layout is built
/// from.
struct AnalysisHistoryRow: View {
    let entry: AnalysisResultSnapshot
    /// Rendered against this instant, so every row in the list ages against
    /// one reading of the clock.
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(age)
                    .font(.fbLabel)
                    .foregroundStyle(Color.fbInkSecondary)
                Spacer(minLength: 8)
                if let feedback = entry.feedback {
                    // The verdict, not a button: the history shows what was
                    // said about a recommendation, and re-rating an old one
                    // belongs to the analysis it was given on.
                    Image(systemName: feedback.symbolName(isSelected: true))
                        .font(.caption)
                        .foregroundStyle(Color.fbMuted)
                }
            }
            Text(preview)
                .font(.subheadline)
                .foregroundStyle(Color.fbInk)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The marker-free recommendation: the raw text would put asterisks into
    /// the preview and read them out in VoiceOver.
    private var preview: String {
        AnalysisTextFormatter.plainText(from: entry.text)
    }

    /// What VoiceOver reads — the opening of the recommendation, not all of
    /// it. `.lineLimit(2)` shortens the row visually but not for a screen
    /// reader, which would otherwise read some 200 words per row on a list of
    /// twenty. The whole text is one tap away in `AnalysisHistoryDetailView`.
    private var previewSnippet: String {
        let flattened = preview.replacingOccurrences(of: "\n", with: " ")
        guard flattened.count > Self.snippetLength else { return flattened }
        return String(flattened.prefix(Self.snippetLength)) + "…"
    }

    /// Roughly the two lines the row shows.
    private static let snippetLength = 120

    private var age: String {
        SyncTimeFormatter.relative(since: entry.generatedAt, now: now)
    }

    private var accessibilityLabel: String {
        var parts = ["Analysis from \(age)"]
        if let feedback = entry.feedback {
            parts.append("rated \(feedback.label)")
        }
        parts.append(previewSnippet)
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
#Preview {
    List {
        AnalysisHistoryRow(
            entry: AnalysisResultSnapshot(
                id: UUID(),
                text: "**Progressive overload**\nAdd 2.5 kg on bench next session and keep the reps.",
                generatedAt: .now.addingTimeInterval(-2 * 3_600),
                context: AnalysisContext(sessionCount: 12, window: .default),
                feedback: .helpful
            ),
            now: .now
        )
        AnalysisHistoryRow(
            entry: AnalysisResultSnapshot(
                id: UUID(),
                text: "Give legs a second slot in the week before you add upper-body volume.",
                generatedAt: .now.addingTimeInterval(-3 * 86_400),
                context: AnalysisContext(sessionCount: 4, window: AnalysisWindow(weeks: 8)),
                feedback: nil
            ),
            now: .now
        )
    }
    .listStyle(.insetGrouped)
}
#endif
