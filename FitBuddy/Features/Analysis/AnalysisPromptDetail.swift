import Foundation

/// How much detail the prompt is built at — one rung of the degradation
/// ladder `AnalysisPromptBudget` picks (TD-1, US-15 AC8, #187).
///
/// Every cut is a list getting shorter, never a figure getting vaguer: the
/// window totals, the per-domain headline figures, the muscle split and the
/// last-seven-days line are the same at every rung, because they are what the
/// recommendation and the report validation (#175, #186) are built on. What
/// degrades is the tail of the lists, where a row costs tokens and adds
/// nothing the aggregates above it do not already carry. Each cut names
/// itself in the prompt, in the "(N … omitted)" form #173 established, so the
/// model reads a shortened list as shortened rather than as the whole window.
///
/// ## The ladder, and how it maps onto #187's
///
/// The issue asks for four steps. Two of them describe a prompt that no
/// longer exists — #183 rebuilt the endurance half as an aggregate and the
/// comparison windows as headline figures — so they are already true at
/// **every** rung and cost nothing to honour:
///
/// | #187's step | Here |
/// |---|---|
/// | 1. cardio session list → weekly aggregate | already so: `EndurancePromptSection` lists no session, only window totals, per-sport rows and per-week rows (#183) |
/// | 2. strength session list capped at 20 | rung 1 |
/// | 3. Exercises section capped at 6 | rung 2 |
/// | 4. comparison window headline figures only | already so: `comparisonSection` in both domains is four lines (#183) |
///
/// Rung 3 is this type's own addition, for the case the issue's steps cannot
/// reach: a widened 13-week window renders thirteen per-week rows in each
/// domain, and those are the last long list left once the two session lists
/// are capped. It keeps the most recent weeks **that recorded training**, not
/// the most recent weeks — on a widened window those are two very different
/// sets, and `weekRows(in:isEmpty:)` explains why.
///
/// ## Why the exercise cap travels with the prompt
///
/// `AnalysisReportEvidence` re-derives the listed exercises to check a
/// progression card against them (#175). If the prompt listed six and the
/// check knew ten, a card could be validated against an exercise the model
/// was never shown — the one thing a budget must not cause. The cap is
/// therefore carried on `AnalysisPrompt` and handed to
/// `AnalysisPromptBuilder.listedExercises(…)` with the reads (#178), so the
/// section and its validation are one list by construction.
struct AnalysisPromptDetail: Equatable, Sendable {
    /// Sessions the strength session list names individually.
    let listedSessions: Int

    /// Movements the Exercises section lists — and, with it, the movements a
    /// progression card may be validated against.
    let listedExercises: Int

    /// How many per-week rows a domain renders, or `nil` for every week of the
    /// window.
    ///
    /// Counted in weeks **that recorded a session**, not in calendar weeks
    /// from the reference day — see `weekRows(in:isEmpty:)`.
    let listedWeeks: Int?

    /// The prompt as #173 to #186 built it: nothing is given up.
    static let full = AnalysisPromptDetail(
        listedSessions: AnalysisPromptBuilder.maxListedSessions,
        listedExercises: AnalysisPromptBuilder.maxListedExercises,
        listedWeeks: nil
    )

    /// The rungs, in order. The first one that fits the budget is the prompt
    /// that is sent; when none does, the last one is — the ladder is what the
    /// app gives up, not a reason to refuse an analysis, and at a sixteenth of
    /// the smallest context window there is room to spare either way.
    ///
    /// Every cap is clamped against the rung above it, so lowering
    /// `maxListedSessions` or `maxListedExercises` can never make a later rung
    /// *wider* than an earlier one and turn the ladder into a loop that never
    /// shrinks the prompt.
    static let ladder: [AnalysisPromptDetail] = [
        .full,
        AnalysisPromptDetail(
            listedSessions: min(20, full.listedSessions),
            listedExercises: full.listedExercises,
            listedWeeks: nil
        ),
        AnalysisPromptDetail(
            listedSessions: min(20, full.listedSessions),
            listedExercises: min(6, full.listedExercises),
            listedWeeks: nil
        ),
        AnalysisPromptDetail(
            listedSessions: min(20, full.listedSessions),
            listedExercises: min(6, full.listedExercises),
            listedWeeks: 4
        ),
    ]

    /// Whether this rung is the untouched prompt — what a test asserting "a
    /// Hevy-only window is unchanged" reads.
    var isFull: Bool { self == .full }

    /// Which per-week rows a domain renders, newest first, and the line that
    /// says what was left out.
    ///
    /// **The cut is made at the weeks that recorded training, not at the most
    /// recent calendar weeks**, and that is the whole difficulty of this rung.
    /// It only fires on a widened window, and a widened window exists *because
    /// the last four weeks held nothing* (`AnalysisWindow.resolve`, #87) — so
    /// "the four most recent weeks" is precisely the four empty ones, and a
    /// first version of this method would have printed four rows of zeros and
    /// dropped the nine weeks the person actually trained in. Weeks without a
    /// session are therefore skipped first, and the cap then applies to what
    /// is left.
    ///
    /// Dropping an empty row loses nothing: each row carries its own absolute
    /// position ("5 weeks back"), so a week that is not printed is a week with
    /// no sessions, which is exactly what its row would have said. The footer
    /// states both facts, and the totals above the section cover the whole
    /// window either way.
    ///
    /// **Each domain cuts at its own weeks.** An earlier version insisted the
    /// two halves cut identically; once the rows are chosen by "did this
    /// domain train that week", identical cuts would mean printing a zero row
    /// in one half to match a real one in the other. The absolute labels make
    /// a missing week unambiguous in either section.
    ///
    /// - Parameters:
    ///   - window: The analysed window, whose `weeks` is the full row count.
    ///   - isEmpty: Whether week `index` holds no session of this domain — 0
    ///     is the week ending on the reference day. Asked rather than computed
    ///     here, because the section buckets the sessions anyway and this type
    ///     has no business knowing about dates.
    /// - Returns: The week indices to render, newest first, and a footer, or
    ///   `nil` when every week is rendered and there is nothing to announce.
    func weekRows(
        in window: AnalysisWindow,
        isEmpty: (Int) -> Bool = { _ in false }
    ) -> (indices: [Int], footer: String?) {
        let all = Array(0..<window.weeks)
        guard let listedWeeks, listedWeeks < window.weeks else { return (all, nil) }
        let recorded = all.filter { !isEmpty($0) }
        // Nothing recorded anywhere: the section is not rendered at all in
        // that case, but a caller that does render it gets the plain cut
        // rather than an empty list.
        guard !recorded.isEmpty else {
            return (Array(all.prefix(listedWeeks)), footer(omittedRecordedWeeks: 0, window: window))
        }
        let listed = Array(recorded.prefix(listedWeeks))
        guard listed.count < all.count else { return (listed, nil) }
        return (listed, footer(omittedRecordedWeeks: recorded.count - listed.count, window: window))
    }

    /// The one line that announces the cut: which rows are missing and why,
    /// and that the figures above the section are unaffected.
    private func footer(omittedRecordedWeeks omitted: Int, window: AnalysisWindow) -> String {
        let spread = "the totals above cover all \(window.weeks) weeks"
        guard omitted > 0 else {
            return "(Weeks without sessions are not listed; \(spread).)"
        }
        return "(Weeks without sessions are not listed. Of the weeks with sessions, the most "
            + "recent are shown and \(CountFormatter.labelled(omitted, singular: "earlier one")) "
            + "omitted; \(spread).)"
    }
}
