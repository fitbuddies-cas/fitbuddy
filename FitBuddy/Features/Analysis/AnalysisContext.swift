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
    /// (US-15 AC4).
    ///
    /// A second breakdown rather than one derived from `sessionCounts`,
    /// because the two answer different questions and no longer line up:
    /// ADR-012 made the normalized sport (`ActivityKind.isEndurance`) the
    /// arbiter of what endurance is, so a Strava `WeightTraining` session is
    /// named under Strava on the line and counted as strength in the warning. Derived from the sources
    /// where nothing finer was recorded — see
    /// `init(sessionCounts:window:profile:)`.
    let domainCounts: [AnalysisDomain: Int]
    /// Of those sessions, the ones that actually reached the prompt, per
    /// domain — the basis the thin-data rule is judged on.
    ///
    /// Since #183 every session of the window reaches the model, so the two
    /// differ only where the user's profile says they should: under
    /// "Strength" the endurance sessions are counted on the line — the user
    /// logged them — and deliberately left out of the analysis (#185). That is
    /// the same shape #182 needed when three Hevy and three Strava strength
    /// sessions were six on the line and three in the model's hands.
    ///
    /// Its keys are therefore the domains the analysis *covers*: a domain that
    /// is absent was not judged at all, and a domain mapped to zero was
    /// covered and empty. Defaults to `domainCounts` where nothing finer is
    /// known — a stored row from before this distinction, or a fixture.
    let analysedCounts: [AnalysisDomain: Int]
    /// Sessions the window held whose source could not be established — a
    /// stored row whose breakdown did not survive (see `SessionCountFormat`).
    ///
    /// Kept apart from `sessionCounts` rather than blamed on Hevy: a row that
    /// really held three lifts and twenty runs must not come back as "23 Hevy
    /// sessions". The line falls back to the bare "23 sessions", which is the
    /// most the row can still justify.
    let unattributedSessionCount: Int
    /// The period actually analysed.
    let window: AnalysisWindow
    /// Which profile the run was made under (US-15 AC1, #185) — `nil` for a
    /// stored row from before the choice existed, and for a fixture that does
    /// not care.
    ///
    /// Part of the basis for the same reason the window is: the profile
    /// decided which domains reached the prompt, so two recommendations drawn
    /// from the same week can differ with nothing on screen to explain it.
    /// `AnalysisContextView` names it, and the history row carries it as a
    /// chip.
    let analysisProfile: AnalysisProfile?
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
    ///     sessions, so their totals have to agree — `counts(in:from:)` counts
    ///     them in one pass over the window for exactly that reason.
    ///   - analysedCounts: The part of `domainCounts` that reached the prompt,
    ///     `nil` where the two are the same. Zero entries survive here, unlike
    ///     in the other two maps: "covered, and empty" is a statement, while a
    ///     source that delivered nothing is simply not part of the basis.
    ///   - analysisProfile: The profile the run was made under (#185). `nil`
    ///     leaves the line without one, which is what a fixture and a row from
    ///     before the choice mean.
    init(
        sessionCounts: [ConnectorSource: Int],
        domainCounts: [AnalysisDomain: Int],
        analysedCounts: [AnalysisDomain: Int]? = nil,
        window: AnalysisWindow,
        analysisProfile: AnalysisProfile? = nil,
        profile: TrainingProfile = TrainingProfile()
    ) {
        let domains = domainCounts.filter { $0.value > 0 }
        self.sessionCounts = sessionCounts.filter { $0.value > 0 }
        self.domainCounts = domains
        self.analysedCounts = analysedCounts ?? domains
        self.unattributedSessionCount = 0
        self.window = window
        self.analysisProfile = analysisProfile
        self.profile = profile
    }

    /// A basis whose sessions were only ever counted per source, with the
    /// domains read off those sources: a stored row from before #182, and the
    /// fixtures and previews built the same way.
    init(
        sessionCounts: [ConnectorSource: Int],
        window: AnalysisWindow,
        analysisProfile: AnalysisProfile? = nil,
        profile: TrainingProfile = TrainingProfile()
    ) {
        let domains = sessionCounts.reduce(into: [AnalysisDomain: Int]()) { counts, entry in
            counts[AnalysisDomain(source: entry.key), default: 0] += entry.value
        }
        self.init(
            sessionCounts: sessionCounts,
            domainCounts: domains,
            window: window,
            analysisProfile: analysisProfile,
            profile: profile
        )
    }

    /// A single-source basis, which before #182 was the only kind there was:
    /// every session counted came from Hevy. Kept for the fixtures, previews
    /// and stored rows that predate the split.
    init(
        sessionCount: Int,
        window: AnalysisWindow,
        analysisProfile: AnalysisProfile? = nil,
        profile: TrainingProfile = TrainingProfile()
    ) {
        self.init(
            sessionCounts: [.hevy: sessionCount],
            window: window,
            analysisProfile: analysisProfile,
            profile: profile
        )
    }

    /// A basis whose breakdown could not be read back: how many sessions the
    /// run saw is known, where they came from and what they were is not.
    ///
    /// Only `AnalysisResultStore` builds one, and only for a row whose stored
    /// breakdown is unreadable. The line then names the total and no source,
    /// and the thin-data rule falls back to that total — there is no domain to
    /// judge, and calling a lost breakdown "thin" would invent a verdict.
    init(
        unattributedSessionCount: Int,
        window: AnalysisWindow,
        analysisProfile: AnalysisProfile? = nil,
        profile: TrainingProfile = TrainingProfile()
    ) {
        self.sessionCounts = [:]
        self.domainCounts = [:]
        self.analysedCounts = [:]
        self.unattributedSessionCount = max(0, unattributedSessionCount)
        self.window = window
        self.analysisProfile = analysisProfile
        self.profile = profile
    }

    /// The sessions of a window, counted per source for the context line and
    /// per domain for the thin-data warning (US-15 AC4, #182) — the two
    /// breakdowns the main initializer takes.
    ///
    /// One pass over the same sessions, so the two breakdowns cannot disagree
    /// about how many there were. They do differ in *where* a session lands:
    /// the source is where it came from, the domain is what was trained
    /// (`ActivityKind.isEndurance`, ADR-012 — not `isCardio`, which is how
    /// the row is displayed), and a Strava strength session is named under
    /// Strava and counted as strength.
    ///
    /// Counted from `start`, not over everything passed in: the cache is read
    /// wide enough for the widest rung of the ladder and its comparison
    /// window, and reporting those sessions as the data basis would overstate
    /// it by a factor of six.
    ///
    /// A source with nothing in the window never enters the dictionary, so a
    /// connector the user has linked but not used stays out of the line.
    ///
    /// Lives here rather than on `AnalysisViewModel` (#248): the run and
    /// `MockAnalysisSeeder` both build a context from it, and a second copy of
    /// this loop would let a UI test assert a breakdown the app itself never
    /// computes.
    static func counts(
        in summaries: [WorkoutSummary],
        from start: Date
    ) -> (sources: [ConnectorSource: Int], domains: [AnalysisDomain: Int]) {
        var sources: [ConnectorSource: Int] = [:]
        var domains: [AnalysisDomain: Int] = [:]
        for summary in summaries where summary.startTime >= start {
            sources[summary.source, default: 0] += 1
            domains[AnalysisDomain(summary: summary), default: 0] += 1
        }
        return (sources, domains)
    }

    /// Sessions in the window across all sources — the figure the thin-data
    /// rule was written against before the split.
    var sessionCount: Int {
        sessionCounts.values.reduce(0, +) + unattributedSessionCount
    }

    /// Of those, the ones the model was actually shown.
    ///
    /// Falls back to the whole basis where no analysed breakdown is known — a
    /// row whose sources could not be read. Judging that as zero would warn
    /// about thin data on a recommendation built from twenty sessions.
    var analysedSessionCount: Int {
        analysedCounts.isEmpty ? sessionCount : analysedCounts.values.reduce(0, +)
    }

    /// The domains this analysis covered at all — the ones the thin-data rule
    /// has anything to say about.
    ///
    /// The user's choice since #185: `AnalysisViewModel` fills `analysedCounts`
    /// with the domains `analysisProfile` covers, so under "Strength" a thin
    /// endurance base is not this analysis's problem — it was never its
    /// subject. Where no profile was recorded it is still read off the
    /// sessions that reached the prompt.
    var analysedDomains: Set<AnalysisDomain> { Set(analysedCounts.keys) }

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

    /// Sessions the window holds in one domain, whether or not they reached
    /// the prompt.
    func sessionCount(in domain: AnalysisDomain) -> Int {
        domainCounts[domain] ?? 0
    }

    /// Of those, the ones the model was shown — what the thin-data warning
    /// reports.
    func analysedSessionCount(in domain: AnalysisDomain) -> Int {
        analysedCounts[domain] ?? 0
    }

    /// The counted part of the context line: `"14 Hevy · 9 Strava sessions"`
    /// (US-15 AC4).
    ///
    /// The whole window, not just the part that reached the prompt: the line
    /// says what the app read, and a session it read and then dropped is still
    /// something the user logged.
    ///
    /// The noun is carried once at the end rather than repeated per source:
    /// "14 Hevy sessions · 9 Strava sessions" is a list of two basises, and
    /// this is one. Sources with nothing in the window are left out entirely —
    /// naming a connected but idle Polar as "0 Polar" would make an untouched
    /// source look like a considered input.
    ///
    /// A basis with no source to name falls back to the bare count: a stored
    /// row from before #36 recorded none ("0 sessions"), and one whose
    /// breakdown did not survive still knows its total ("23 sessions").
    var basisDescription: String {
        let counted = countedSources
        let noun = Self.sessionNoun(for: sessionCount)
        guard !counted.isEmpty else { return "\(sessionCount) \(noun)" }
        let parts = counted.map { "\(sessionCount(from: $0)) \($0.displayName)" }
        return "\(parts.joined(separator: " · ")) \(noun)"
    }

    /// Why the period is not the usual four weeks — `nil` when it is (#87).
    ///
    /// Past tense and phrased around the covered window, because a restored
    /// recommendation (#97) is read hours or days after its run: "the last four
    /// weeks" would then mean a period the analysis never saw, and the empty
    /// weeks are the *most recent* ones inside the widened window, not the ones
    /// before it.
    ///
    /// "No sessions", without a qualifier, since #183. `AnalysisWindow.resolve`
    /// now ladders on every session the cache holds, because every one of them
    /// reaches the prompt: an endurance session is sectioned rather than
    /// dropped, so twelve recent runs keep the window at four weeks instead of
    /// widening past them. Note and basis line therefore describe the same
    /// sessions again, and the domain qualifier #182 needed — for exactly as
    /// long as the ladder read the source — would now be the wrong wording.
    var widenedWindowNote: String? {
        guard !window.isDefault else { return nil }
        return """
        This analysis covered \(window.weeks) weeks — its most recent \
        \(AnalysisWindow.default.weeks) held no sessions.
        """
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

    /// The domains the analysis covered that it saw too little of, in
    /// `AnalysisDomain.allCases` order (US-15 AC4).
    ///
    /// Judged on `analysedCounts`, so the verdict is about what the model was
    /// shown. Two cases turn on that:
    ///
    /// - A domain the analysis did not cover is absent, not thin. One Strava
    ///   run next to fourteen Hevy sessions must not put a thin-endurance
    ///   warning on a recommendation that says nothing about running, and
    ///   someone who only ever connected Hevy is not short of endurance data.
    /// - A domain whose sessions were counted but dropped is thin on what was
    ///   left. Three Hevy and three Strava strength sessions are six on the
    ///   line and three in the prompt, and it is the three the warning is
    ///   about.
    ///
    /// - A domain the *profile* left out is absent for the same reason
    ///   (#185). Fourteen Hevy sessions and one run under "Strength" warn
    ///   about nothing: the run was counted on the line, because the user
    ///   logged it, and deliberately not analysed.
    var thinDomains: [AnalysisDomain] {
        AnalysisDomain.allCases.filter { domain in
            guard analysedDomains.contains(domain) else { return false }
            return analysedSessionCount(in: domain) < Self.thinDataThreshold
        }
    }

    /// Whether the warning of US-6 AC2 belongs on screen.
    ///
    /// The analysed total is checked as well as the domains, so a basis nobody
    /// recorded — a stored row from before #36, which reads as zero sessions —
    /// still warns rather than passing as solid data on a technicality.
    var isThin: Bool {
        analysedSessionCount < Self.thinDataThreshold || !thinDomains.isEmpty
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
        let named = thin.map { domain in
            let counted = CountFormatter.labelled(
                analysedSessionCount(in: domain),
                singular: "session"
            )
            return "Thin \(domain.displayName) data — \(counted)"
        }
        return "\(named.joined(separator: " · ")). \(advice)"
    }

    /// The bare noun, for the one place `CountFormatter.labelled(_:singular:)`
    /// does not fit: `basisDescription` carries it once after a list of
    /// per-source counts, not attached to a number of its own.
    ///
    /// "Sessions" rather than "workouts": Hevy calls a logged entry a workout,
    /// but the same word is what the recommendation uses for a planned one,
    /// and the two must not blur in a line whose whole job is to say what was
    /// counted.
    private static func sessionNoun(for count: Int) -> String {
        count == 1 ? "session" : "sessions"
    }
}
