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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(Color.fbAccent)
                    .frame(width: 6, height: 6)
                basis
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

    /// `"Based on 12 Hevy sessions · last 4 weeks"`, with the counted part
    /// emphasised as in `design/fb-screens.jsx:544` — the number is what the
    /// line exists for.
    ///
    /// The sources are joined by hand rather than via `Array.formatted()`:
    /// that style follows the device locale and would drop a German "und" into
    /// an English sentence once #33/#35 make `sources` a real list.
    ///
    /// "Sessions" rather than "workouts": Hevy calls a logged entry a workout,
    /// but the same word is what the recommendation uses for a planned one,
    /// and the two must not blur in a line whose whole job is to say what was
    /// counted.
    private var basis: Text {
        let sessions = context.sessionCount == 1 ? "session" : "sessions"
        let counted = "\(context.sessionCount) \(context.sources.joined(separator: ", ")) \(sessions)"
        return Text("Based on ")
            + Text(counted).foregroundColor(.fbInk).fontWeight(.semibold)
            + Text(" · last \(context.window.weeks) weeks")
            + profileSuffix
    }

    /// The profile, appended to the basis line when there is one (US-13 AC4):
    /// "· goal: improve endurance · 1–3 years of strength training". It went
    /// into the prompt, so a basis line without it would be incomplete — and
    /// the user would have no way to see that a stale goal is still steering
    /// the recommendation.
    private var profileSuffix: Text {
        var parts: [String] = []
        if let goal = context.profile.goal {
            parts.append("goal: \(goal.displayName.lowercased())")
        }
        if let experience = context.profile.experience {
            parts.append("\(experience.displayName.lowercased()) of strength training")
        }
        guard !parts.isEmpty else { return Text("") }
        return Text(" · " + parts.joined(separator: " · "))
    }

    /// Why the period is not the usual four weeks. Carried over from
    /// `AnalysisWindowNote`: what the user cannot work out on their own is
    /// that this recommendation reaches further back than the app normally
    /// looks, and that an empty recent window is the reason.
    ///
    /// Past tense and phrased around the covered window, because a restored
    /// recommendation (#97) is read hours or days after its run: "the last
    /// four weeks" would then mean a period the analysis never saw, and the
    /// empty weeks are the *most recent* ones inside the widened window, not
    /// the ones before it.
    private var widenedNote: String {
        """
        This analysis covered \(context.window.weeks) weeks — its most recent \
        \(AnalysisWindow.default.weeks) held no sessions.
        """
    }

    /// US-6 AC2. Deliberately blunt: a recommendation drawn from three
    /// sessions reads exactly as confident as one drawn from twenty, and this
    /// line is the only thing that tells the two apart. `fbWarn` is the token
    /// the rest of the app warns in (`SyncStatusView`, `LLMKeysView`), so an
    /// explicit warning reads as one here too.
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
        .foregroundStyle(Color.fbWarn)
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
