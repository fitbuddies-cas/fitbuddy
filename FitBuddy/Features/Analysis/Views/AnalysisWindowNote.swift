import SwiftUI

/// Names the period an analysis actually covers, when it is not the 4-week
/// default (#87).
///
/// Only shown for a widened window. Repeating "last 4 weeks" for the normal
/// case would add a line that never changes; the intro card and the dashboard
/// CTA already say it. What the user cannot know on their own is that this
/// particular recommendation reaches further back than usual — and why.
struct AnalysisWindowNote: View {
    let window: AnalysisWindow

    var body: some View {
        if !window.isDefault {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.caption2)
                Text("""
                No sessions in the last \(AnalysisWindow.default.weeks) weeks — \
                this analysis covers the last \(window.weeks) weeks.
                """)
                .font(.caption)
            }
            .foregroundStyle(Color.fbInkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.fbCardSubtle)
            .clipShape(RoundedRectangle(cornerRadius: FBRadius.card))
            .accessibilityElement(children: .combine)
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 12) {
        AnalysisWindowNote(window: AnalysisWindow(weeks: 8))
        AnalysisWindowNote(window: AnalysisWindow(weeks: 13))
    }
    .padding(16)
    .background(Color.fbBackground)
}
#endif
