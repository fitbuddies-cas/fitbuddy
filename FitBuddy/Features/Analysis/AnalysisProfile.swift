import Foundation

/// What the user asks this analysis to be about: their strength training,
/// their endurance training, or the load of both together (US-15 AC1, #185).
///
/// One verdict per screen is the point. "You're ready to progress" and
/// "Recover this week" exclude each other, and over a mixed week they can both
/// be true — lifting may be ready to go up while the running legs need a
/// break. Without a choice the model has to pick one of the two for the user,
/// and it picks blind. With one, the recommendation is about something the
/// user named.
///
/// A profile is not a domain. `AnalysisDomain` is a property of a session —
/// what it was — while a profile is a choice about which of those domains this
/// run covers, which is why "Overall load" exists here and has no counterpart
/// there.
enum AnalysisProfile: String, CaseIterable, Sendable {
    case strength
    case endurance
    case overallLoad

    /// The label on the segmented control and in the context line. Title case,
    /// because it is read as a name of its own — unlike
    /// `AnalysisDomain.displayName`, which sits mid-sentence in a warning.
    var displayName: String {
        switch self {
        case .strength: return "Strength"
        case .endurance: return "Endurance"
        case .overallLoad: return "Overall load"
        }
    }

    /// The SF Symbol the history chip carries, so a row is recognisable
    /// before its text is read.
    var symbolName: String {
        switch self {
        case .strength: return "dumbbell"
        case .endurance: return "figure.run"
        case .overallLoad: return "chart.bar"
        }
    }

    /// The domains this profile analyses, in `AnalysisDomain.allCases` order.
    ///
    /// This is the single rule everything else reads: which sections the
    /// prompt carries, which domains `AnalysisContext` reports as covered, and
    /// therefore which of them the thin-data warning of US-6 AC2 may name.
    var domains: [AnalysisDomain] {
        switch self {
        case .strength: return [.strength]
        case .endurance: return [.endurance]
        case .overallLoad: return AnalysisDomain.allCases
        }
    }

    /// Whether a session of this domain is part of the analysis.
    func covers(_ domain: AnalysisDomain) -> Bool {
        domains.contains(domain)
    }

    /// Whether the run judges strength and endurance against each other — the
    /// question the week-structure section of US-15 AC2 exists to answer.
    var coversBothDomains: Bool { domains.count > 1 }

    /// The profile this window is actually analysed under — what the prompt
    /// is built from, what the context line names, and what the history row
    /// records.
    ///
    /// Two things happen here, and neither is a choice made on the user's
    /// behalf:
    ///
    /// - **A profile with nothing to analyse widens.** The picker only offers
    ///   a profile the window has sessions for, but a sync can land between
    ///   the moment the options were computed and the moment "Analyze" is
    ///   tapped, and a remembered choice can outlive the data it was made
    ///   about. Without this the run would build a prompt with no section in
    ///   it and pay a provider to read an empty page.
    /// - **A profile covering more than the window holds narrows.** "Overall
    ///   load" over a window of nothing but lifts *is* a strength analysis —
    ///   the prompt is byte for byte the same — so the line and the history
    ///   chip say "Strength" rather than promising a comparison that was never
    ///   made. This is what makes the implicit profile of US-15 AC1 the one a
    ///   Hevy-only install is recorded with, without the screen ever having
    ///   shown a picker.
    ///
    /// An empty window keeps "Overall load": there is nothing there to name it
    /// after, and the run ends in `.noTrainingData` regardless.
    func resolved(for summaries: [WorkoutSummary]) -> AnalysisProfile {
        let present = Set(summaries.map(AnalysisDomain.init(summary:)))
        let covered = present.intersection(domains)
        guard !covered.isEmpty else {
            // Nothing of this profile is here; fall back to what is.
            return Self.covering(present)
        }
        return Self.covering(covered)
    }

    /// The profile whose domains are exactly `domains` — one case per domain,
    /// "Overall load" for both and for none.
    private static func covering(_ domains: Set<AnalysisDomain>) -> AnalysisProfile {
        guard domains.count == 1, let only = domains.first else { return .overallLoad }
        switch only {
        case .strength: return .strength
        case .endurance: return .endurance
        }
    }
}
