import SwiftUI

/// Names the data basis the recommendation rests on: sources, period, session
/// count — and warns when that basis is thin (US-6, #36).
///
/// Replaces the narrower `AnalysisWindowNote` of #87, which named the period
/// only when the fallback ladder had widened it. US-6 AC1 asks for the period
/// every time, so the widened case is no longer a separate line but a second
/// sentence on this one: what the analysis read, and — where it is not
/// obvious — why it reached further back than usual.
struct AnalysisContextView: View {
    let context: AnalysisContext

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "text.magnifyingglass")
                    .font(.caption2)
                Text(basis)
                    .font(.caption)
            }
            if !context.window.isDefault {
                Text(widenedNote)
                    .font(.caption)
            }
            if context.isThin {
                thinDataWarning
            }
        }
        .foregroundStyle(Color.fbInkSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.fbCardSubtle)
        .clipShape(RoundedRectangle(cornerRadius: FBRadius.card))
        .accessibilityElement(children: .combine)
    }

    /// `"Based on 12 Hevy sessions · last 4 weeks"`.
    ///
    /// "Sessions" rather than "workouts": Hevy calls a logged entry a workout,
    /// but the same word is what the recommendation uses for a planned one,
    /// and the two must not blur in a line whose whole job is to say what was
    /// counted.
    private var basis: String {
        let sessions = context.sessionCount == 1 ? "session" : "sessions"
        return """
        Based on \(context.sessionCount) \(context.sources.formatted()) \
        \(sessions) · last \(context.window.weeks) weeks
        """
    }

    /// Why the period is not the usual four weeks. Carried over from
    /// `AnalysisWindowNote`: what the user cannot work out on their own is
    /// that this recommendation reaches further back than the app normally
    /// looks, and that an empty recent window is the reason.
    private var widenedNote: String {
        """
        No sessions in the last \(AnalysisWindow.default.weeks) weeks, so the \
        window was widened.
        """
    }

    /// US-6 AC2. Deliberately blunt: a recommendation drawn from three
    /// sessions reads exactly as confident as one drawn from twenty, and this
    /// line is the only thing that tells the two apart.
    private var thinDataWarning: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption2)
            Text("""
            Thin data — fewer than \(AnalysisContext.thinDataThreshold) \
            sessions. Treat the recommendation as a starting point.
            """)
            .font(.caption)
        }
        .foregroundStyle(Color.fbInk)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 12) {
        AnalysisContextView(context: AnalysisContext(sessionCount: 12, window: .default))
        AnalysisContextView(context: AnalysisContext(sessionCount: 3, window: .default))
        AnalysisContextView(context: AnalysisContext(sessionCount: 7, window: AnalysisWindow(weeks: 8)))
        AnalysisContextView(context: AnalysisContext(sessionCount: 1, window: AnalysisWindow(weeks: 13)))
    }
    .padding(16)
    .background(Color.fbBackground)
}
#endif
