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
            if let profileLine {
                Text(profileLine)
                    .font(.caption)
                    // Indented under the sentence, past the dot, as in the
                    // mock (`FBAnalysisContextLine`, #196).
                    .padding(.leading, 14)
            }
            if let widenedNote = context.widenedWindowNote {
                Text(widenedNote)
                    .font(.caption)
            }
            if let warning = context.thinDataWarning {
                thinDataWarning(warning)
            }
        }
        .foregroundStyle(Color.fbInkSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.fbCardSubtle)
        .clipShape(RoundedRectangle(cornerRadius: FBRadius.card))
        .accessibilityElement(children: .combine)
    }

    /// `"Based on 14 Hevy · 9 Strava sessions · last 4 weeks"`, with the
    /// counted part emphasised as in `FBAnalysisContextLine`
    /// (`design/fb-screens.jsx`, #196) — the number is what the line exists
    /// for.
    ///
    /// The counted part is built in `AnalysisContext` rather than here: which
    /// sources are named, in which order, and how they are joined is a
    /// statement about the data basis (US-15 AC4) that has to be testable
    /// without a view, and the same string also has to hold for a restored
    /// row.
    private var basis: Text {
        Text("Based on ")
            + Text(context.basisDescription).foregroundColor(.fbInk).fontWeight(.semibold)
            + Text(" · last \(context.window.weeks) weeks")
    }

    /// The profile, as a second line under the basis when there is one
    /// (US-13 AC4): "Goal: Build muscle · 1–3 years training", the form of
    /// `FBAnalysisContextLine` in `design/fb-screens.jsx` (#196). It went into
    /// the prompt, so a basis without it would be incomplete — and the user
    /// would have no way to see that a stale goal is still steering the
    /// recommendation.
    ///
    /// Its own line rather than more dots on the first: appended, the caption
    /// runs to three lines on an iPhone SE, and "less than a year of strength
    /// training" reads badly mid-sentence. No profile → no line; half a
    /// profile → the half that is set.
    private var profileLine: String? {
        var parts: [String] = []
        if let goal = context.profile.goal {
            parts.append("Goal: \(goal.displayName)")
        }
        if let experience = context.profile.experience {
            parts.append("\(experience.displayName) training")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    /// US-6 AC2, naming the thin domain since US-15 AC4 — the wording comes
    /// from `AnalysisContext.thinDataWarning` for the same reason as `basis`.
    /// `fbWarn` is the token the rest of the app warns in (`SyncStatusView`,
    /// `LLMKeysView`), so an explicit warning reads as one here too.
    private func thinDataWarning(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption2)
            Text(text)
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
        AnalysisContextView(
            context: AnalysisContext(sessionCounts: [.hevy: 14, .strava: 9], window: .default)
        )
        AnalysisContextView(
            context: AnalysisContext(sessionCounts: [.hevy: 14, .strava: 2, .polar: 1], window: .default)
        )
        AnalysisContextView(
            context: AnalysisContext(
                sessionCount: 14,
                window: .default,
                profile: TrainingProfile(goal: .buildMuscle, experience: .oneToThreeYears)
            )
        )
        AnalysisContextView(
            context: AnalysisContext(
                sessionCount: 3,
                window: AnalysisWindow(weeks: 8),
                profile: TrainingProfile(goal: .improveEndurance)
            )
        )
    }
    .padding(16)
    .background(Color.fbBackground)
}
#endif
