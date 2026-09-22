import Foundation

/// Which analysis profiles the screen offers and which one starts selected
/// (US-15 AC1, #185).
///
/// Its own type rather than two computed properties on the view model: the
/// rule is what the acceptance criteria are written about — "only Hevy, no
/// choice", "Hevy and Strava, three options with Overall load preselected" —
/// and a rule the tests can only reach through a view model with a cache stub
/// behind it is a rule nobody reads.
struct AnalysisProfileOptions: Equatable, Sendable {
    /// The profiles worth offering, in `AnalysisProfile.allCases` order.
    /// Never empty: with nothing cached the analysis is still a strength
    /// analysis, it just has no data yet.
    let available: [AnalysisProfile]
    /// The one the screen starts on.
    let preselected: AnalysisProfile

    /// Whether the user is given a choice at all.
    ///
    /// A segmented control with one segment is not a choice, it is a label —
    /// and a Hevy-only install has exactly one, which is why US-15 AC1 asks
    /// for no picker there and an implicit "Strength" (#185).
    var isChoice: Bool { available.count > 1 }

    /// - Parameters:
    ///   - domainCounts: The sessions of the analysed window, per domain —
    ///     `AnalysisContext.domainCounts`, counted the same way.
    ///   - remembered: The profile the user picked for their last analysis, or
    ///     `nil` on the first run. It wins over the computed default whenever
    ///     it is still on offer: someone who chose "Strength" last week did
    ///     not choose it for one run.
    init(domainCounts: [AnalysisDomain: Int], remembered: AnalysisProfile? = nil) {
        let present = AnalysisDomain.allCases.filter { (domainCounts[$0] ?? 0) > 0 }
        var offered = present.map(Self.profile(for:))
        // "Overall load" is only a third answer where there is a second domain
        // to weigh against the first. With one domain it would be the same
        // analysis under a second name, and a user picking between two
        // identical options learns nothing from the difference.
        if present.count > 1 {
            offered.append(.overallLoad)
        }
        let available = offered.isEmpty ? [.strength] : offered
        self.available = AnalysisProfile.allCases.filter { available.contains($0) }

        // The default of US-15 AC1: several kinds of training in the window →
        // the load of all of it; one kind → that one.
        //
        // **Deliberate reading of the criterion.** #171 AC1 phrases it as
        // "several *sources*", and #185 as "two sources with sessions". Since
        // ADR-012 the source is no longer what decides whether an analysis has
        // two halves to weigh — the sport is. Two connected sources that both
        // deliver nothing but strength work are one domain, and preselecting
        // "Overall load" for them would start the user on a profile covering a
        // domain their window has no session in. Where the two readings differ
        // at all, this one is the honest half of the pair; in the case the
        // criterion was written for — Hevy plus Strava, lifts plus runs — they
        // agree.
        let fallback = self.available.contains(.overallLoad)
            ? AnalysisProfile.overallLoad
            : (self.available.first ?? .strength)
        if let remembered, self.available.contains(remembered) {
            self.preselected = remembered
        } else {
            self.preselected = fallback
        }
    }

    private static func profile(for domain: AnalysisDomain) -> AnalysisProfile {
        switch domain {
        case .strength: return .strength
        case .endurance: return .endurance
        }
    }
}
