import SwiftUI

/// The resting state of the analysis screen: what the analysis is, what it
/// sends, the profile it will be about, and the button that starts it (#32,
/// #185).
struct AnalysisIntroView: View {
    /// `false` only while a run is in flight — the intro is not on screen
    /// then, but the button must not be tappable twice in the same frame.
    let canStart: Bool
    /// Which profiles this cache is worth offering and which one is selected
    /// (US-15 AC1). Decided in `AnalysisViewModel`; this view only renders it.
    var options = AnalysisProfileOptions(domainCounts: [:])
    var selection: AnalysisProfile = .strength
    var onSelect: (AnalysisProfile) -> Void = { _ in }
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FBCard(padding: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    // No provider name here: which one answers is only
                    // decided once the run starts and the chain resolves, so
                    // naming one now could turn out to be wrong (#79).
                    Text("AI".uppercased())
                        .font(.fbLabel)
                        .tracking(0.6)
                        .foregroundStyle(Color.fbMuted)
                    Text("Ready for a progression check?")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.fbInk)
                    Text(explanation)
                        .font(.subheadline)
                        .foregroundStyle(Color.fbInkSecondary)
                }
            }

            if options.isChoice {
                profilePicker
            }

            Button("Analyze with AI", action: onStart)
                .buttonStyle(.fb(.accent))
                .disabled(!canStart)
        }
    }

    /// What the run will read. The second sentence appears only where there is
    /// a choice to explain — a Hevy-only install has one kind of training, and
    /// naming a profile it cannot change would be a distinction without a
    /// difference (US-15 AC1).
    private var explanation: String {
        let base = """
        Your AI provider reads the last 4 weeks of your cached training data \
        and compares them with the 4 weeks before, then names one concrete \
        next step.
        """
        guard options.isChoice else { return base }
        return base + " Choose what this analysis should be about."
    }

    /// The segmented control above the button (design 3.1).
    ///
    /// Above and not below: the choice changes what the button does, and a
    /// control placed after the action it modifies is read too late. Only the
    /// profiles the window holds data for are offered — an "Endurance" segment
    /// over a cache without a single run would promise an analysis that cannot
    /// be given.
    private var profilePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Analysis profile".uppercased())
                .font(.fbLabel)
                .tracking(0.6)
                .foregroundStyle(Color.fbMuted)
            Picker("Analysis profile", selection: binding) {
                ForEach(options.available, id: \.self) { profile in
                    Text(profile.displayName).tag(profile)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!canStart)
        }
    }

    /// The picker writes through the view model rather than into view state:
    /// the choice steers the next run and is remembered past this screen,
    /// which is a decision and not a rendering detail (MVVM).
    private var binding: Binding<AnalysisProfile> {
        Binding(get: { selection }, set: onSelect)
    }
}

#if DEBUG
#Preview("Ready") {
    AnalysisIntroView(canStart: true, onStart: {})
        .padding(16)
        .background(Color.fbBackground)
}

/// Lifts and runs in the window: three options, "Overall load" preselected
/// (US-15 AC1).
#Preview("Mixed sources") {
    AnalysisIntroView(
        canStart: true,
        options: AnalysisProfileOptions(domainCounts: [.strength: 14, .endurance: 9]),
        selection: .overallLoad,
        onSelect: { _ in },
        onStart: {}
    )
    .padding(16)
    .background(Color.fbBackground)
}

/// A mostly-running window with the profile switched to "Endurance" — the
/// picker keeps the segments the data supports, and the selection is the
/// user's, not the default's.
#Preview("Endurance chosen") {
    AnalysisIntroView(
        canStart: true,
        options: AnalysisProfileOptions(domainCounts: [.strength: 2, .endurance: 9]),
        selection: .endurance,
        onSelect: { _ in },
        onStart: {}
    )
    .padding(16)
    .background(Color.fbBackground)
}
#endif
