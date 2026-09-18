import Foundation

/// What the recommendation on screen actually rests on: which sources, which
/// period, how many sessions from each (US-6, #36; US-15 AC4, #182).
///
/// The user cannot see the prompt, so without this line the recommendation is
/// an assertion they have to take on faith. Naming the data basis is what lets
/// them tell "the model read my last four weeks" from "the model read three
/// sessions and guessed" — and AC2 makes the second case say so out loud.
///
/// The window travels with the count rather than being assumed to be the
/// default: the fallback ladder of #87 widens it when the last four weeks are
/// empty, and a context line naming a period the analysis did not use would be
/// the opposite of transparency.
struct AnalysisContext: Equatable, Sendable {
    /// Sessions the analysis window holds, per source — the sessions the
    /// prompt was built from, not everything in the cache.
    ///
    /// Per source rather than one number since #182: with Strava and Polar
    /// feeding the same analysis, "23 sessions" hides whether that is a
    /// balanced block or twenty runs next to three lifts, and the two lead to
    /// opposite recommendations. Sources with no session in the window are not
    /// in the dictionary at all — see `init(sessionCounts:window:profile:)`.
    let sessionCounts: [ConnectorSource: Int]
    /// The same sessions split by what they were, not by where they came from
    /// (US-15 AC4) — the basis the thin-data rule is applied to.
    ///
    /// A second breakdown rather than one derived from `sessionCounts`,
    /// because the two answer different questions and no longer line up:
    /// ADR-012 made `WorkoutSummary.isCardio` the arbiter of what endurance
    /// is, so a Strava `WeightTraining` session is named under Strava on the
    /// line and counted as strength in the warning. Derived from the sources
    /// where nothing finer was recorded — see
    /// `init(sessionCounts:window:profile:)`.
    let domainCounts: [AnalysisDomain: Int]
    /// The period actually analysed.
    let window: AnalysisWindow
    /// What the user told the analysis about themselves (US-13 AC4, #192).
    /// Part of the basis for the same reason the session count is: it went
    /// into the prompt, so a line that listed everything else and not this
    /// would be a basis with a hole in it.
    var profile = TrainingProfile()

    /// - Parameters:
    ///   - sessionCounts: Counts per source. Zero and negative entries are
    ///     dropped here rather than at every read: a source that delivered
    ///     nothing must not reach the context line (US-15 AC4), and keeping
    ///     `[.hevy: 0]` distinct from `[:]` would make two contexts describing
    ///     the same empty window compare unequal. The same holds for
    ///     `domainCounts`.
    ///   - domainCounts: Counts per domain. Both breakdowns describe the same
    ///     sessions, so their totals have to agree — `AnalysisViewModel` counts
    ///     them in one pass over the window for exactly that reason.
    init(
        sessionCounts: [ConnectorSource: Int],
        domainCounts: [AnalysisDomain: Int],
        window: AnalysisWindow,
        profile: TrainingProfile = TrainingProfile()
    ) {
        self.sessionCounts = sessionCounts.filter { $0.value > 0 }
        self.domainCounts = domainCounts.filter { $0.value > 0 }
        self.window = window
        self.profile = profile
    }

    /// A basis whose sessions were only ever counted per source, with the
    /// domains read off those sources: a stored row from before #182, and the
    /// fixtures and previews built the same way.
    init(
        sessionCounts: [ConnectorSource: Int],
        window: AnalysisWindow,
        profile: TrainingProfile = TrainingProfile()
    ) {
        let domains = sessionCounts.reduce(into: [AnalysisDomain: Int]()) { counts, entry in
            counts[AnalysisDomain(source: entry.key), default: 0] += entry.value
        }
        self.init(
            sessionCounts: sessionCounts,
            domainCounts: domains,
            window: window,
            profile: profile
        )
    }

    /// A single-source basis, which before #182 was the only kind there was:
    /// every session counted came from Hevy. Kept for the fixtures, previews
    /// and stored rows that predate the split.
    init(
        sessionCount: Int,
        window: AnalysisWindow,
        profile: TrainingProfile = TrainingProfile()
    ) {
        self.init(sessionCounts: [.hevy: sessionCount], window: window, profile: profile)
    }

    /// Sessions in the window across all sources — the figure the thin-data
    /// rule was written against before the split.
    var sessionCount: Int { sessionCounts.values.reduce(0, +) }

    /// The sources that actually delivered a session, in
    /// `ConnectorSource.allCases` order.
    ///
    /// A fixed order rather than the dictionary's: a context line whose
    /// sources swap places between two runs reads as if the data had changed,
    /// and the same stored row has to render identically every time it is
    /// opened.
    var countedSources: [ConnectorSource] {
        ConnectorSource.allCases.filter { sessionCount(from: $0) > 0 }
    }

    /// Sessions the window holds from one source.
    func sessionCount(from source: ConnectorSource) -> Int {
        sessionCounts[source] ?? 0
    }

    /// Sessions the window holds in one domain.
    func sessionCount(in domain: AnalysisDomain) -> Int {
        domainCounts[domain] ?? 0
    }

    /// The counted part of the context line: `"14 Hevy · 9 Strava sessions"`
    /// (US-15 AC4).
    ///
    /// The noun is carried once at the end rather than repeated per source:
    /// "14 Hevy sessions · 9 Strava sessions" is a list of two basises, and
    /// this is one. Sources with nothing in the window are left out entirely —
    /// naming a connected but idle Polar as "0 Polar" would make an untouched
    /// source look like a considered input.
    ///
    /// An empty basis still names a number ("0 sessions"): the run that
    /// produced it fails with `.noTrainingData` before the line is ever drawn,
    /// but a stored row from before #36 recorded no count, and "Based on
    /// sessions" would be worse than the honest zero.
    var basisDescription: String {
        let counted = countedSources
        let noun = Self.sessionNoun(for: sessionCount)
        guard !counted.isEmpty else { return "\(sessionCount) \(noun)" }
        let parts = counted.map { "\(sessionCount(from: $0)) \($0.displayName)" }
        return "\(parts.joined(separator: " · ")) \(noun)"
    }

    /// Below this many sessions in the window, the data basis is called thin
    /// (US-6 AC2) — per domain since #182.
    ///
    /// Five because the prompt compares the window with the equally long one
    /// before it and reports per-week volume: under roughly one session a week
    /// a single missed or extra workout moves every number the model reasons
    /// over, and a confident recommendation drawn from that reads far firmer
    /// than the data underneath it. That argument is about one discipline's
    /// numbers, so it applies to each domain on its own and not to their sum.
    static let thinDataThreshold = 5

    /// The domains the analysis saw that are below the threshold, in
    /// `AnalysisDomain.allCases` order (US-15 AC4).
    ///
    /// A domain with *no* session is not thin, it is absent: someone who has
    /// only ever connected Hevy is not short of endurance data, they are not
    /// having endurance analysed. Warning about it would make the app look as
    /// if it expected a second sport.
    ///
    /// #185 adds the analysis profile. Until then the domains are read off the
    /// data; afterwards the chosen profile decides which of them to judge —
    /// under "Strength" a thin endurance base is not the analysis's problem.
    var thinDomains: [AnalysisDomain] {
        AnalysisDomain.allCases.filter { domain in
            let count = sessionCount(in: domain)
            return count > 0 && count < Self.thinDataThreshold
        }
    }

    /// Whether the warning of US-6 AC2 belongs on screen.
    ///
    /// The total is checked as well as the domains, so a basis nobody recorded
    /// — a stored row from before #36, which reads as zero sessions — still
    /// warns rather than passing as solid data on a technicality.
    var isThin: Bool {
        sessionCount < Self.thinDataThreshold || !thinDomains.isEmpty
    }

    /// The warning of US-6 AC2 in full, naming the thin domain where there is
    /// one to name (US-15 AC4) — `nil` when the basis is not thin.
    ///
    /// Deliberately blunt: a recommendation drawn from three sessions reads
    /// exactly as confident as one drawn from twenty, and this line is the
    /// only thing that tells the two apart. Naming the domain is what makes it
    /// actionable across sources — "thin data" over a mixed basis leaves the
    /// user guessing which half of their training the model was short of.
    var thinDataWarning: String? {
        guard isThin else { return nil }
        let advice = "Treat the recommendation as a starting point."
        let thin = thinDomains
        guard !thin.isEmpty else {
            return "Thin data — fewer than \(Self.thinDataThreshold) sessions. \(advice)"
        }
        let named = thin.map { domain -> String in
            let count = sessionCount(in: domain)
            return "Thin \(domain.displayName) data — \(count) \(Self.sessionNoun(for: count))"
        }
        return "\(named.joined(separator: " · ")). \(advice)"
    }

    /// "Sessions" rather than "workouts": Hevy calls a logged entry a workout,
    /// but the same word is what the recommendation uses for a planned one,
    /// and the two must not blur in a line whose whole job is to say what was
    /// counted.
    private static func sessionNoun(for count: Int) -> String {
        count == 1 ? "session" : "sessions"
    }
}
